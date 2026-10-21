import Foundation
import CryptoKit
import Security

/// The set of tokens we hold after a successful login.
struct GMToken: Codable {
    /// Token used as Bearer on GM mobile API calls.
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isValid: Bool { Date() < expiresAt.addingTimeInterval(-60) }
}

/// UIKit-free OAuth token plumbing shared by the app and the widget extension:
/// PKCE generation, the B2C code→token exchange, the GM token-exchange, and
/// silent refresh. The *interactive* web login lives in `GMAuthSession`
/// (app target only) because it needs `ASWebAuthenticationSession`.
struct GMTokenService {

    // MARK: - PKCE

    func makePKCE() -> (verifier: String, challenge: String) {
        let verifier = Self.codeVerifier()
        return (verifier, Self.codeChallenge(for: verifier))
    }

    func randomState() -> String { Self.randomString(32) }

    func authorizeURL(challenge: String, state: String, loginHint: String? = nil) -> URL {
        var comps = URLComponents(string: GMAPI.b2cAuthorizeBase + "/authorize")!
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: GMAPI.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: GMAPI.redirectURI),
            .init(name: "scope", value: GMAPI.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "response_mode", value: "query"),
            // Extra params the MyChevrolet app sends so the B2C policy themes and
            // routes the page correctly (mirrors OnStarJS).
            .init(name: "bundleID", value: "com.gm.myChevrolet"),
            .init(name: "brand", value: "chevrolet"),
            .init(name: "channel", value: "lightreg"),
            .init(name: "ui_locales", value: "en-US"),
            .init(name: "mode", value: "dark"),
            .init(name: "evar25",
                  value: "mobile_mychevrolet_chevrolet_us_app_launcher_sign_in_or_create_account")
        ]
        if let loginHint, !loginHint.isEmpty {
            items.append(.init(name: "login_hint", value: loginHint))
        }
        comps.queryItems = items
        return comps.url!
    }

    // MARK: - Exchanges

    /// Trade an authorization code for a GM API token (via the MS access token).
    func exchange(code: String, verifier: String, deviceId: String) async throws -> GMToken {
        let msAccessToken = try await exchangeCodeForMSToken(code: code, verifier: verifier)
        return try await exchangeForGMToken(msAccessToken: msAccessToken, deviceId: deviceId)
    }

    func refresh(_ token: GMToken) async throws -> GMToken {
        guard let refresh = token.refreshToken else { throw OnStarError.notAuthenticated }
        var req = URLRequest(url: GMAPI.gmTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": GMAPI.clientId
        ])
        return try await Self.parseGMToken(from: req)
    }

    private func exchangeCodeForMSToken(code: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: GMAPI.b2cAuthorizeBase + "/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "grant_type": "authorization_code",
            "client_id": GMAPI.clientId,
            "code": code,
            "redirect_uri": GMAPI.redirectURI,
            "code_verifier": verifier
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw OnStarError.tokenExchangeFailed(http.statusCode, "MS-token: " + String(decoding: data, as: UTF8.self))
        }
        // The GM API token-exchange wants the B2C *access* token (scoped to the
        // custom Test.Read API scope), not the id_token. Prefer access_token.
        struct MSResponse: Decodable { let id_token: String?; let access_token: String? }
        let ms = try JSONDecoder().decode(MSResponse.self, from: data)
        guard let token = ms.access_token ?? ms.id_token else {
            throw OnStarError.authFailed("Microsoft token missing.")
        }
        return token
    }

    private func exchangeForGMToken(msAccessToken: String, deviceId: String) async throws -> GMToken {
        var req = URLRequest(url: GMAPI.gmTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Mirrors OnStarJS getGMAPIToken exactly: the subject token is the MS
        // *access* token, typed as access_token, with the device id. No client_id.
        req.httpBody = Self.form([
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token": msAccessToken,
            "subject_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "scope": "onstar gmoc user_trailer user msso priv",
            "device_id": deviceId
        ])
        return try await Self.parseGMToken(from: req, label: "GM-token")
    }

    private static func parseGMToken(from req: URLRequest, label: String = "GM-token") async throws -> GMToken {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw OnStarError.tokenExchangeFailed(http.statusCode, label + ": " + String(decoding: data, as: UTF8.self))
        }
        struct GMResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?

            enum CodingKeys: String, CodingKey {
                case access_token, refresh_token, expires_in
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                access_token = try c.decode(String.self, forKey: .access_token)
                refresh_token = try c.decodeIfPresent(String.self, forKey: .refresh_token)
                // GM sends expires_in as either a number or a quoted string.
                if let n = try? c.decodeIfPresent(Int.self, forKey: .expires_in) {
                    expires_in = n
                } else if let s = try? c.decodeIfPresent(String.self, forKey: .expires_in) {
                    expires_in = Int(s)
                } else {
                    expires_in = nil
                }
            }
        }
        do {
            let gm = try JSONDecoder().decode(GMResponse.self, from: data)
            return GMToken(
                accessToken: gm.access_token,
                refreshToken: gm.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(gm.expires_in ?? 1800))
            )
        } catch {
            throw OnStarError.decoding("\(label): \(error.localizedDescription) — body: " + Self.snippet(data))
        }
    }

    // MARK: - Helpers

    static func queryItem(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    /// A short, log-safe excerpt of a response body for error messages.
    static func snippet(_ data: Data, max: Int = 300) -> String {
        let s = String(decoding: data, as: UTF8.self)
        return s.count > max ? String(s.prefix(max)) + "…" : s
    }

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func randomString(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func form(_ params: [String: String]) -> Data {
        params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?/")
        return set
    }()
}
