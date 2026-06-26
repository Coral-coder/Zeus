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

    func authorizeURL(challenge: String, state: String) -> URL {
        var comps = URLComponents(string: GMAPI.b2cAuthorizeBase + "/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: GMAPI.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: GMAPI.redirectURI),
            .init(name: "scope", value: GMAPI.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "response_mode", value: "query")
        ]
        return comps.url!
    }

    // MARK: - Exchanges

    /// Trade an authorization code for a GM API token (via the MS id_token).
    func exchange(code: String, verifier: String) async throws -> GMToken {
        let msToken = try await exchangeCodeForMSToken(code: code, verifier: verifier)
        return try await exchangeForGMToken(msIDToken: msToken)
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
            throw OnStarError.tokenExchangeFailed(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        struct MSResponse: Decodable { let id_token: String?; let access_token: String? }
        let ms = try JSONDecoder().decode(MSResponse.self, from: data)
        guard let token = ms.id_token ?? ms.access_token else {
            throw OnStarError.authFailed("Microsoft token missing.")
        }
        return token
    }

    private func exchangeForGMToken(msIDToken: String) async throws -> GMToken {
        var req = URLRequest(url: GMAPI.gmTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "subject_token": msIDToken,
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "client_id": GMAPI.clientId,
            "scope": "msso role_owner priv onstar gmoc user user_trailer"
        ])
        return try await Self.parseGMToken(from: req)
    }

    private static func parseGMToken(from req: URLRequest) async throws -> GMToken {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw OnStarError.tokenExchangeFailed(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        struct GMResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
        }
        do {
            let gm = try JSONDecoder().decode(GMResponse.self, from: data)
            return GMToken(
                accessToken: gm.access_token,
                refreshToken: gm.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(gm.expires_in ?? 1800))
            )
        } catch {
            throw OnStarError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    static func queryItem(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
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
