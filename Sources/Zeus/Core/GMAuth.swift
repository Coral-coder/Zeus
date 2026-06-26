import Foundation
import CryptoKit

/// Performs GM's (unofficial) OnStar login entirely on-device by driving the
/// Azure AD B2C custom-policy flow the way the MyChevrolet app does:
///
///   1. GET the authorize URL → scrape `SETTINGS` (csrf + transId) from the page
///   2. POST credentials to `SelfAsserted`
///   3. GET `…/CombinedSigninAndSignup/confirmed`
///   4. If MFA is required, POST a generated TOTP code, then confirm again
///   5. Capture the `code` from the redirect to the app's custom scheme
///   6. Exchange the code for the GM API token (via `GMTokenService`)
///
/// GM's flow is undocumented and changes; `steps` records each stage so failures
/// surface exactly where they happened. ToS-gray; personal use only.
final class GMAuth: NSObject {
    private let config: OnStarConfig
    private let tokens = GMTokenService()
    private var capturedRedirect: URL?
    private(set) var steps: [String] = []
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always   // carry B2C's x-ms-cpim-* cookies across steps
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    init(config: OnStarConfig) {
        self.config = config
    }

    // MARK: - Entry point

    func authenticate() async throws -> GMToken {
        // The session strongly retains its delegate (self); release it when done.
        defer { session.finishTasksAndInvalidate() }
        let pkce = tokens.makePKCE()
        let state = tokens.randomState()
        let authorizeURL = tokens.authorizeURL(challenge: pkce.challenge, state: state)

        // 1. Load the hosted sign-in page.
        let (pageData, _) = try await get(authorizeURL, step: "authorize")
        var settings = try parseSettings(pageData, step: "authorize")

        // 2. Submit email + password.
        try await selfAsserted(settings: settings,
                               body: ["request_type": "RESPONSE",
                                      "signInName": config.email,
                                      "password": config.password],
                               step: "password")

        // 3. Confirm the credential step → either a code (no MFA) or the MFA page.
        switch try await confirm(settings: settings, step: "confirm-credentials") {
        case .code(let code):
            return try await finish(code: code, verifier: pkce.verifier)
        case .page(let mfaData):
            // 4. MFA: read the TOTP page's SETTINGS, submit a generated code.
            settings = try parseSettings(mfaData, step: "mfa-page")
            let otp = try totpCode()
            steps.append("generated TOTP code")
            // GM's TOTP control posts the 6-digit code; field name varies by
            // policy version, so send the common ones.
            try await selfAsserted(settings: settings,
                                   body: ["request_type": "RESPONSE",
                                          "otpCode": otp,
                                          "verificationCode": otp],
                                   step: "mfa-submit")
            switch try await confirm(settings: settings, step: "confirm-mfa") {
            case .code(let code):
                return try await finish(code: code, verifier: pkce.verifier)
            case .page:
                throw fail("no authorization code after MFA", step: "confirm-mfa")
            }
        }
    }

    // MARK: - B2C steps

    private func selfAsserted(settings: B2CSettings, body: [String: String], step: String) async throws {
        guard let url = settings.selfAssertedURL else { throw fail("missing SelfAsserted URL", step: step) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(settings.csrf, forHTTPHeaderField: "X-CSRF-TOKEN")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = Self.form(body)
        let (data, http) = try await send(req, step: step)
        // SelfAsserted returns JSON like {"status":"200"}; anything else is a failure.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = obj["status"] as? String, status != "200" {
            throw fail("SelfAsserted status \(status): \(obj["message"] as? String ?? "")", step: step)
        }
        if http.statusCode != 200 {
            throw fail("SelfAsserted HTTP \(http.statusCode): \(Self.snippet(data))", step: step)
        }
    }

    private enum ConfirmResult {
        case code(String)   // redirected to the app scheme with an auth code
        case page(Data)     // returned another HTML page (e.g. the MFA step)
    }

    /// GET the confirmed endpoint. Either the flow redirects to the app's custom
    /// scheme (→ `.code`) or it returns the next HTML page (→ `.page`).
    private func confirm(settings: B2CSettings, step: String) async throws -> ConfirmResult {
        guard let url = settings.confirmedURL else { throw fail("missing confirmed URL", step: step) }
        capturedRedirect = nil
        let (data, _) = try await get(url, step: step)
        if let redirect = capturedRedirect {
            if let code = Self.queryItem(redirect, "code") {
                steps.append("\(step): captured code")
                return .code(code)
            }
            if let err = Self.queryItem(redirect, "error_description") {
                throw fail("B2C error: \(err)", step: step)
            }
        }
        return .page(data)
    }

    private func finish(code: String, verifier: String) async throws -> GMToken {
        steps.append("exchanging code for GM token")
        return try await tokens.exchange(code: code, verifier: verifier)
    }

    // MARK: - HTTP

    @discardableResult
    private func get(_ url: URL, step: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        return try await send(req, step: step)
    }

    private func send(_ request: URLRequest, step: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else { throw fail("no HTTP response", step: step) }
            steps.append("\(step): HTTP \(http.statusCode)")
            return (data, http)
        } catch let e as OnStarError {
            throw e
        } catch {
            throw fail("network error: \(error.localizedDescription)", step: step)
        }
    }

    // MARK: - SETTINGS parsing

    private struct B2CSettings {
        let csrf: String
        let transId: String
        let tenantPath: String   // e.g. /gmb2cprod.onmicrosoft.com/B2C_1A_..._SignUpOrSignIn
        let policy: String

        var base: String { "https://custlogin.gm.com\(tenantPath)" }
        var selfAssertedURL: URL? {
            var c = URLComponents(string: "\(base)/SelfAsserted")
            c?.queryItems = [.init(name: "tx", value: transId), .init(name: "p", value: policy)]
            return c?.url
        }
        var confirmedURL: URL? {
            var c = URLComponents(string: "\(base)/api/CombinedSigninAndSignup/confirmed")
            c?.queryItems = [
                .init(name: "rememberMe", value: "false"),
                .init(name: "csrf_token", value: csrf),
                .init(name: "tx", value: transId),
                .init(name: "p", value: policy)
            ]
            return c?.url
        }
    }

    private func parseSettings(_ data: Data, step: String) throws -> B2CSettings {
        let html = String(decoding: data, as: UTF8.self)
        guard let json = Self.extractJSONObject(html, after: "SETTINGS = "),
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else {
            throw fail("couldn't find SETTINGS on page (len \(html.count))", step: step)
        }
        guard let csrf = obj["csrf"] as? String, let transId = obj["transId"] as? String else {
            throw fail("SETTINGS missing csrf/transId", step: step)
        }
        let hosts = obj["hosts"] as? [String: Any]
        let tenant = (hosts?["tenant"] as? String) ?? ""
        let policy = tenant.split(separator: "/").last.map(String.init) ?? "B2C_1A_SEAMLESS_MOBILE_SignUpOrSignIn"
        return B2CSettings(csrf: csrf, transId: transId, tenantPath: tenant, policy: policy)
    }

    // MARK: - TOTP (RFC 6238, SHA1, 6 digits, 30s)

    private func totpCode() throws -> String {
        guard let key = Self.base32Decode(config.totpSecret) else {
            throw fail("invalid TOTP secret (not base32)", step: "totp")
        }
        var counter = UInt64(Date().timeIntervalSince1970 / 30).bigEndian
        let counterData = Data(bytes: &counter, count: 8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: key))
        let hash = Array(mac)
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary = (UInt32(hash[offset] & 0x7f) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        return String(format: "%06u", binary % 1_000_000)
    }

    // MARK: - Helpers

    private func fail(_ message: String, step: String) -> OnStarError {
        let trail = (steps + ["✗ \(step): \(message)"]).joined(separator: " | ")
        return .authFailed(trail)
    }

    /// First ~240 chars of a response body, whitespace-collapsed — for surfacing
    /// GM's actual error text in the diagnostic trail.
    private static func snippet(_ data: Data) -> String {
        let s = String(decoding: data.prefix(600), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(s.prefix(240))
    }

    private static func form(_ params: [String: String]) -> Data {
        params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)!
    }

    private static func queryItem(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value
    }

    /// Pull a balanced `{...}` JSON object out of `s`, starting after `marker`.
    /// Brace-matches while respecting string literals, so embedded `;`/`{`/`}`
    /// inside string values don't truncate it.
    private static func extractJSONObject(_ s: String, after marker: String) -> String? {
        guard let r = s.range(of: marker) else { return nil }
        let sub = s[r.upperBound...]
        guard let start = sub.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var idx = start
        while idx < sub.endIndex {
            let ch = sub[idx]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { return String(sub[start...idx]) }
                }
            }
            idx = sub.index(after: idx)
        }
        return nil
    }

    static func base32Decode(_ string: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var lookup = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() { lookup[c] = UInt8(i) }
        var bits = 0, value = 0
        var out = [UInt8]()
        for c in string.uppercased() where c != "=" {
            guard let v = lookup[c] else { return nil }
            value = (value << 5) | Int(v)
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return out.isEmpty ? nil : Data(out)
    }
}

// MARK: - Redirect capture

extension GMAuth: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url else { completionHandler(request); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            completionHandler(request)          // follow normal redirects
        } else {
            capturedRedirect = url              // app's custom scheme — stop & capture
            completionHandler(nil)
        }
    }
}
