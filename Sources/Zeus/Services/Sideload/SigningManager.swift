import Foundation

/// App Store Connect API credentials — the "sign in" for the sideloader. Stored
/// in the Keychain; never imported per app.
struct ASCCredentials: Codable, Equatable {
    var issuerID: String
    var keyID: String
    var p8PEM: String          // contents of the AuthKey_XXXX.p8
    var appleEmail: String     // used only as the CSR subject email
}

/// Ties the whole "sign in and Zeus does the rest" flow together: with the
/// stored ASC key it mints a development certificate (from an on-device CSR),
/// registers the device, generates a per-app provisioning profile via Apple's
/// official API, and re-signs the `.ipa` with zsign.
actor SigningManager {
    static let shared = SigningManager()

    // Cached across apps within a session.
    private var certificate: AppStoreConnectService.Certificate?
    private var keyPEM: String?
    private var deviceID: String?

    // MARK: - Credentials (sign-in)

    nonisolated var credentials: ASCCredentials? {
        KeychainStore.load(ASCCredentials.self, for: .ascCredentials)
    }
    nonisolated var isSignedIn: Bool { credentials != nil }

    nonisolated func saveCredentials(_ creds: ASCCredentials) throws {
        try KeychainStore.save(creds, for: .ascCredentials)
    }

    nonisolated func signOut() {
        KeychainStore.delete(.ascCredentials)
    }

    /// Validate the stored key against the API.
    func verify() async throws {
        let svc = try service()
        try await svc.verify()
    }

    // MARK: - Re-sign

    /// Re-sign `ipaData` for `bundleID` on the device identified by `udid`.
    func resign(ipaData: Data, bundleID: String, udid: String) async throws -> Data {
        let svc = try service()

        // Certificate + private key (mint once, reuse for the session).
        if certificate == nil || keyPEM == nil {
            let email = credentials?.appleEmail ?? "zeus@zeus.local"
            let csr = try CSR.generate(commonName: "Zeus Sideload", emailAddress: email)
            keyPEM = csr.privateKeyPEM
            certificate = try await svc.createDevelopmentCertificate(csrPEM: csr.csrPEM)
        }
        guard let certificate, let keyPEM else { throw Err.state }

        // Device (register once).
        if deviceID == nil {
            deviceID = try await svc.ensureDevice(udid: udid, name: "Zeus Sideload Device")
        }
        guard let deviceID else { throw Err.state }

        // Per-app bundle id + development profile.
        let bundleIDId = try await svc.ensureBundleID(identifier: bundleID, name: bundleID.replacingOccurrences(of: ".", with: " "))
        let profile = try await svc.createProfile(
            name: "Zeus \(bundleID) \(Int(Date().timeIntervalSince1970))",
            bundleIDId: bundleIDId, certificateID: certificate.id, deviceIDs: [deviceID])

        // Stage the identity files and hand off to zsign.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let certURL = dir.appendingPathComponent("cert.der")
        let keyURL = dir.appendingPathComponent("key.pem")
        let provURL = dir.appendingPathComponent("app.mobileprovision")
        try certificate.der.write(to: certURL)
        try Data(keyPEM.utf8).write(to: keyURL)
        try profile.write(to: provURL)

        return try Signer.resign(ipaData: ipaData, with: .init(
            certPath: certURL, keyPath: keyURL, provisionPath: provURL, password: "", newBundleID: nil))
    }

    // MARK: -

    enum Err: LocalizedError {
        case notSignedIn, state
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in with your App Store Connect API key first."
            case .state: return "Signing state error."
            }
        }
    }

    private func service() throws -> AppStoreConnectService {
        guard let c = credentials else { throw Err.notSignedIn }
        return AppStoreConnectService(issuerID: c.issuerID, keyID: c.keyID, p8PEM: c.p8PEM)
    }
}
