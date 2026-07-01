import Foundation
import SwiftUI
import UIKit

/// Orchestrates the on-device sideloader: owns the loopback server + install
/// store, stages `.ipa`s from any of the four sources, and opens the OTA install
/// / trust links. Native successor to `ipa_sideload`'s `src/server.js` glue.
@MainActor
final class SideloadModel: ObservableObject {
    let port: UInt16 = 8787

    @Published var installs: [SideloadInstall] = []
    @Published var status: String = "Tap a source below to stage a build."
    @Published var busy = false
    @Published var serverReady = false
    /// Flipped when an `.ipa` is opened into Zeus so the hidden panel can surface.
    @Published var presentSideload = false
    /// Signed in with an App Store Connect API key (enables auto re-signing).
    @Published var signedIn = SigningManager.shared.isSignedIn
    /// The device UDID, once the enrollment profile has reported it.
    @Published var udid: String?

    private let store = SideloadStore()
    private var server: LoopbackServer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    /// Silent-audio keep-alive so the server survives backgrounding (Safari/Settings/installd).
    private let keepAlive = KeepAlive()
    /// Captures the device UDID reported by the enrollment profile (see DeviceEnrollment).
    let enrollment = UDIDCapture()

    init() { installs = store.list() }

    /// The captured device UDID, if the enrollment profile has been installed.
    var capturedUDID: String? { enrollment.udid }

    // MARK: - Server lifecycle

    func startServer() {
        // Already up and listening — nothing to do.
        if let s = server, s.isRunning { serverReady = true; keepAlive.start(); return }
        // A stale/dead listener (killed while the app was backgrounded) — tear it
        // down and recreate, otherwise we'd report "ready" on a dead socket and
        // installd/Safari would hit "cannot connect".
        server?.stop()
        server = nil
        serverReady = false
        do {
            let result = try LoopbackIdentity.ensure()
            let store = self.store
            let port = self.port
            let certDER = result.certificateDER
            let capture = self.enrollment
            let server = LoopbackServer(port: port) { method, path, query, body in
                SideloadModel.route(method: method, path: path, query: query, body: body,
                                    store: store, certDER: certDER, port: port, capture: capture)
            }
            server.onStateChange = { [weak self] ready in
                Task { @MainActor in self?.serverReady = ready }
            }
            try server.start(identity: result.identity)
            self.server = server
            keepAlive.start()   // keep the server alive while backgrounded
            status = "Starting local install server…"
        } catch {
            serverReady = false
            status = "Couldn't start local server: \(error.localizedDescription)"
        }
    }

    /// (Re)start the server if needed and wait until it's genuinely listening.
    private func ensureServerReady() async -> Bool {
        startServer()
        for _ in 0..<40 {   // up to ~4s
            if server?.isRunning == true { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return server?.isRunning == true
    }

    func stopServer() {
        server?.stop()
        server = nil
        serverReady = false
        keepAlive.stop()
        endBackground()
    }

    // MARK: - Router (runs off the main actor on the server's queue)

    nonisolated private static func route(method: String, path: String, query: [String: String], body: Data,
                                          store: SideloadStore, certDER: Data, port: UInt16,
                                          capture: UDIDCapture) -> HTTPResponse {
        let base = "https://127.0.0.1:\(port)"

        if path == "/trust" {
            return .text(trustHTML(), contentType: "text/html; charset=utf-8")
        }
        if path == "/trust/ca.mobileconfig" {
            var r = HTTPResponse(contentType: "application/x-apple-aspen-config",
                                 body: Data(TrustProfileBuilder.mobileconfig(certificateDER: certDER).utf8))
            r.headers["Content-Disposition"] = "attachment; filename=\"zeus-sideload.mobileconfig\""
            return r
        }

        // Device UDID enrollment (see DeviceEnrollment).
        if path == "/enroll" {
            var r = HTTPResponse(contentType: "application/x-apple-aspen-config",
                                 body: Data(EnrollmentProfile.mobileconfig(postURL: "\(base)/enroll/receive").utf8))
            r.headers["Content-Disposition"] = "attachment; filename=\"zeus-enroll.mobileconfig\""
            return r
        }
        if path == "/enroll/receive" {
            if let udid = EnrollmentResponse.parseUDID(from: body) { capture.udid = udid }
            return .text("ok")
        }

        // /i/<id>/manifest.plist  or  /i/<id>/app.ipa  (token-gated, no session)
        let comps = path.split(separator: "/").map(String.init)
        if comps.count == 3, comps[0] == "i" {
            let id = comps[1]
            guard let install = store.get(id) else { return .notFound() }
            guard query["t"] == install.installToken else { return .forbidden() }

            if comps[2] == "manifest.plist" {
                let ipaURL = "\(base)/i/\(id)/app.ipa?t=\(install.installToken)"
                let xml = ManifestBuilder.manifest(ipaURL: ipaURL, bundleID: install.bundleID,
                                                   version: install.version, title: install.title)
                return HTTPResponse(contentType: "application/xml", body: Data(xml.utf8))
            }
            if comps[2] == "app.ipa" {
                guard let data = try? Data(contentsOf: store.ipaURL(for: id)) else { return .gone() }
                var r = HTTPResponse(contentType: "application/octet-stream", body: data)
                r.headers["Content-Disposition"] = "attachment; filename=\"\(install.ipaName)\""
                return r
            }
        }
        return .notFound()
    }

    // MARK: - Staging from the four sources

    func handleIncoming(_ url: URL) {
        guard url.pathExtension.lowercased() == "ipa" else { return }
        presentSideload = true
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                await stage(data: data, name: url.lastPathComponent, source: .file(name: url.lastPathComponent))
            } catch {
                status = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func stageFromURL(_ urlString: String) async {
        guard let url = URL(string: urlString), (url.scheme ?? "").hasPrefix("http") else {
            status = "Enter a valid http(s) URL."
            return
        }
        busy = true
        status = "Downloading…"
        defer { busy = false }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                status = "Download failed: HTTP \(http.statusCode)"
                return
            }
            let name = url.lastPathComponent.isEmpty ? "app.ipa" : url.lastPathComponent
            await stage(data: data, name: name, source: .url(urlString))
        } catch {
            status = "Download failed: \(error.localizedDescription)"
        }
    }

    func stageFromGitHub(_ service: GitHubService, owner: String, repo: String, artifact: GitHubService.Artifact) async {
        busy = true
        status = "Downloading \(artifact.name)…"
        defer { busy = false }
        do {
            let zip = try await service.downloadArtifactZip(owner: owner, repo: repo, artifactID: artifact.id)
            await stage(data: zip, name: "\(artifact.name).ipa",
                        source: .github(owner: owner, repo: repo, artifact: artifact.name))
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    func stage(data: Data, name: String, source: IPASource) async {
        busy = true
        status = "Preparing \(name)…"
        defer { busy = false }
        do {
            let resolved = try IPAReader.resolveIPA(data, name: name)
            let meta = try IPAReader.metadata(ipaData: resolved.data, fallbackName: resolved.name)

            // Re-sign with your developer account, if signed in and enrolled.
            var ipaBytes = resolved.data
            var signed = false
            if SigningManager.shared.isSignedIn, let deviceUDID = enrollment.udid {
                status = "Re-signing \(meta.title) for your device…"
                do {
                    ipaBytes = try await SigningManager.shared.resign(
                        ipaData: ipaBytes, bundleID: meta.bundleID, udid: deviceUDID)
                    signed = true
                } catch {
                    status = "Re-sign failed (\(error.localizedDescription)) — staging as-is."
                }
            }

            let install = try store.stage(ipaData: ipaBytes, name: resolved.name,
                                          meta: meta, sourceLabel: source.label)
            installs = store.list()
            status = signed ? "Signed & ready: \(install.title)"
                            : "Ready: \(install.title) · \(install.bundleID)"
            if server == nil { startServer() }
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sign-in (App Store Connect API key) + device enrollment

    func signIn(issuerID: String, keyID: String, p8: String, appleEmail: String) async {
        busy = true
        status = "Verifying your key…"
        defer { busy = false }
        let creds = ASCCredentials(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            p8PEM: p8,
            appleEmail: appleEmail.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try SigningManager.shared.saveCredentials(creds)
            try await SigningManager.shared.verify()
            signedIn = true
            status = "Signed in. Enroll your device, then add a build."
        } catch {
            SigningManager.shared.signOut()
            signedIn = false
            status = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        SigningManager.shared.signOut()
        signedIn = false
    }

    func openEnroll() {
        Task {
            guard await ensureServerReady(), let server,
                  let url = URL(string: "\(server.baseURL)/enroll") else {
                status = "Local server didn't come up — try again."; return
            }
            UIApplication.shared.open(url)
        }
    }

    /// Pull the latest captured UDID into the published property for the UI.
    func refreshEnrollment() { udid = enrollment.udid }

    /// Manually set the device UDID (fallback when the enrollment profile is
    /// rejected by iOS as an unsigned "Profile Service" — modern iOS does that).
    func setManualUDID(_ raw: String) {
        let u = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Accept the two common UDID shapes: 40-hex (older) or 8-4-… (newer).
        let ok = u.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
            || u.range(of: "^[0-9a-f]{8}-[0-9a-f]{16}$", options: .regularExpression) != nil
        guard ok else { status = "That doesn't look like a UDID."; return }
        enrollment.udid = u
        udid = u
        status = "Device UDID set — you can add a build now."
    }

    // MARK: - Install / trust / delete

    func install(_ install: SideloadInstall) {
        Task {
            status = "Preparing install…"
            guard await ensureServerReady(), let server else {
                status = "Local server didn't come up — reopen Sideload and try again."
                return
            }
            beginBackground()   // keep serving through the install fetch
            let manifestURL = "\(server.baseURL)/i/\(install.id)/manifest.plist?t=\(install.installToken)"
            guard let url = URL(string: ManifestBuilder.installLink(manifestURL: manifestURL)) else { return }
            UIApplication.shared.open(url) { [weak self] ok in
                Task { @MainActor in
                    self?.status = ok ? "Requested install of \(install.title)…"
                                      : "iOS refused the install link."
                }
            }
        }
    }

    func openTrust() {
        Task {
            guard await ensureServerReady(), let server,
                  let url = URL(string: "\(server.baseURL)/trust") else {
                status = "Local server didn't come up — try again."; return
            }
            UIApplication.shared.open(url)
        }
    }

    func delete(_ install: SideloadInstall) {
        store.remove(install.id)
        installs = store.list()
    }

    // MARK: - Background keepalive (server must live through the install sheet)

    private func beginBackground() {
        endBackground()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "sideload-install") { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    // MARK: - Trust page (served in Safari on first run)

    nonisolated private static func trustHTML() -> String {
        """
        <!doctype html><meta charset=utf8>
        <meta name=viewport content="width=device-width,initial-scale=1">
        <title>Trust Zeus</title>
        <body style="font:-apple-system,system-ui,sans-serif;max-width:460px;margin:40px auto;padding:0 20px;background:#05080f;color:#eee">
        <h2>Trust this device</h2>
        <p>To install apps from Zeus over the local connection, iOS needs to trust Zeus's certificate. One time only:</p>
        <ol style="line-height:1.7">
        <li><a href="/trust/ca.mobileconfig" style="color:#2be8ff">Download the profile</a></li>
        <li>Settings → <b>Profile Downloaded</b> → Install</li>
        <li>Settings → General → About → <b>Certificate Trust Settings</b> → enable <b>Zeus local root</b></li>
        </ol>
        <p style="color:#9a9aa6;font-size:13px">It will show "Not Verified" — that's expected for a self-signed local certificate.</p>
        </body>
        """
    }
}
