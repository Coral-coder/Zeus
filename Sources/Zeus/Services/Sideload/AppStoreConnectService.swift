import Foundation
import Crypto

/// Minimal App Store Connect API client. This is the "sign in and Zeus does the
/// rest" engine: with your developer-account API key it mints a development
/// certificate from a local CSR, registers your device, and generates a
/// provisioning profile — all via Apple's official API, so nothing here can get
/// your account flagged the way Apple-ID/anisette automation can.
struct AppStoreConnectService {
    let issuerID: String
    let keyID: String
    let p8PEM: String            // the .p8 private key contents (PEM)

    private let base = URL(string: "https://api.appstoreconnect.apple.com/v1")!

    enum ASCError: LocalizedError {
        case token(String)
        case http(Int, String)
        case shape(String)
        var errorDescription: String? {
            switch self {
            case .token(let m): return "Couldn't build the API token: \(m)"
            case .http(let code, let m): return "App Store Connect API \(code): \(m)"
            case .shape(let m): return "Unexpected API response: \(m)"
            }
        }
    }

    struct Certificate { let id: String; let der: Data }

    // MARK: - Auth

    private func token() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": issuerID, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"
        ]
        func seg(_ obj: Any) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            return b64url(data)
        }
        let signingInput = try seg(header) + "." + seg(payload)
        do {
            let key = try P256.Signing.PrivateKey(pemRepresentation: p8PEM)
            let sig = try key.signature(for: Data(signingInput.utf8))
            return signingInput + "." + b64url(sig.rawRepresentation)
        } catch {
            throw ASCError.token(error.localizedDescription)
        }
    }

    private func b64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - REST

    @discardableResult
    private func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ASCError.http(code, String(data: data, encoding: .utf8)?.prefix(400).description ?? "")
        }
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func firstData(_ json: [String: Any]) -> [String: Any]? {
        if let d = json["data"] as? [String: Any] { return d }
        if let arr = json["data"] as? [[String: Any]] { return arr.first }
        return nil
    }

    /// Validate the key by hitting a trivial endpoint; returns the team name if any.
    func verify() async throws {
        _ = try await send("GET", "apps?limit=1")
    }

    // MARK: - Certificate

    func createDevelopmentCertificate(csrPEM: String) async throws -> Certificate {
        let body: [String: Any] = ["data": [
            "type": "certificates",
            "attributes": ["certificateType": "IOS_DEVELOPMENT", "csrContent": csrPEM]
        ]]
        let json = try await send("POST", "certificates", body: body)
        guard let d = firstData(json), let id = d["id"] as? String,
              let attrs = d["attributes"] as? [String: Any],
              let content = attrs["certificateContent"] as? String,
              let der = Data(base64Encoded: content) else {
            throw ASCError.shape("certificate")
        }
        return Certificate(id: id, der: der)
    }

    // MARK: - Device

    /// Register the device by UDID, or return the existing registration's id.
    func ensureDevice(udid: String, name: String) async throws -> String {
        // Already registered?
        let existing = try await send("GET", "devices?filter[udid]=\(udid)&limit=1")
        if let d = firstData(existing), let id = d["id"] as? String { return id }

        let body: [String: Any] = ["data": [
            "type": "devices",
            "attributes": ["name": name, "platform": "IOS", "udid": udid]
        ]]
        let json = try await send("POST", "devices", body: body)
        guard let d = firstData(json), let id = d["id"] as? String else { throw ASCError.shape("device") }
        return id
    }

    // MARK: - Bundle ID

    func ensureBundleID(identifier: String, name: String) async throws -> String {
        let existing = try await send("GET", "bundleIds?filter[identifier]=\(identifier)&limit=1")
        if let d = firstData(existing), let id = d["id"] as? String { return id }

        let body: [String: Any] = ["data": [
            "type": "bundleIds",
            "attributes": ["identifier": identifier, "name": name, "platform": "IOS"]
        ]]
        let json = try await send("POST", "bundleIds", body: body)
        guard let d = firstData(json), let id = d["id"] as? String else { throw ASCError.shape("bundleId") }
        return id
    }

    // MARK: - Profile

    /// Create a development profile and return the `.mobileprovision` bytes.
    func createProfile(name: String, bundleIDId: String, certificateID: String,
                       deviceIDs: [String]) async throws -> Data {
        let body: [String: Any] = ["data": [
            "type": "profiles",
            "attributes": ["name": name, "profileType": "IOS_APP_DEVELOPMENT"],
            "relationships": [
                "bundleId": ["data": ["type": "bundleIds", "id": bundleIDId]],
                "certificates": ["data": [["type": "certificates", "id": certificateID]]],
                "devices": ["data": deviceIDs.map { ["type": "devices", "id": $0] }]
            ]
        ]]
        let json = try await send("POST", "profiles", body: body)
        guard let d = firstData(json), let attrs = d["attributes"] as? [String: Any],
              let content = attrs["profileContent"] as? String,
              let data = Data(base64Encoded: content) else {
            throw ASCError.shape("profile")
        }
        return data
    }
}
