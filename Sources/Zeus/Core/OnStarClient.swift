import Foundation

/// Low-level GM mobile API client: holds the token, lists vehicles, issues
/// remote commands and polls them to completion. UIKit-free so it compiles in
/// both the app and the widget extension. Interactive login is supplied by the
/// app via `login(using:)`; refresh is handled internally.
actor OnStarClient {

    private var token: GMToken?
    private let tokens = GMTokenService()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
        self.token = KeychainStore.load(GMToken.self, for: .gmToken)
    }

    var isAuthenticated: Bool { token != nil }

    // MARK: - Auth

    /// The app passes a closure that performs the interactive web login
    /// (`GMAuthSession.login`) and returns the resulting token.
    func login(using provider: () async throws -> GMToken) async throws {
        let newToken = try await provider()
        try persist(newToken)
    }

    func signOut() {
        token = nil
        KeychainStore.delete(.gmToken)
    }

    private func validToken() async throws -> String {
        guard let token else { throw OnStarError.notAuthenticated }
        if token.isValid { return token.accessToken }
        let refreshed = try await tokens.refresh(token)
        try persist(refreshed)
        return refreshed.accessToken
    }

    private func persist(_ token: GMToken) throws {
        self.token = token
        try KeychainStore.save(token, for: .gmToken)
    }

    // MARK: - Vehicles

    func vehicles() async throws -> [Vehicle] {
        // The garage list is a GraphQL POST with a plain-text body.
        let data = try await postRaw(GMAPI.garageURL,
                                     body: GMAPI.garageQuery,
                                     contentType: "text/plain; charset=utf-8")
        return try VehicleResponseParser.parseVehicles(data)
    }

    func diagnostics(vin: String) async throws -> VehicleSnapshot {
        let payload = try await get(GMAPI.healthStatusURL(vin: vin))
        return try VehicleResponseParser.parseHealthStatus(payload, vin: vin)
    }

    // MARK: - Commands

    @discardableResult
    func runCommand(_ command: VehicleCommand,
                    vin: String,
                    body: Encodable? = nil,
                    timeout: TimeInterval = 90) async throws -> Data {
        let url = GMAPI.commandURL(vin: vin, command: command.rawValue)
        let initial = try await post(url, body: body)

        guard let followURL = CommandPoll.statusURL(from: initial) else {
            return initial
        }

        let deadline = Date().addingTimeInterval(timeout)
        var delay: UInt64 = 3
        while Date() < deadline {
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            let status = try await get(followURL)
            switch CommandPoll.outcome(from: status) {
            case .success(let payload):
                return payload
            case .inProgress:
                delay = min(delay + 2, 10)
                continue
            case .failed(let msg):
                throw OnStarError.commandFailed(command, msg)
            }
        }
        throw OnStarError.commandTimedOut(command)
    }

    // MARK: - HTTP

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req)
    }

    private func post(_ url: URL, body: Encodable?) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        } else {
            req.httpBody = Data("{}".utf8)
        }
        return try await send(req)
    }

    private func postRaw(_ url: URL, body: String, contentType: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        return try await send(req)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var req = request
        let bearer = try await validToken()
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        // GM's mobile API expects its own app headers; without them it 404s/403s.
        for (k, v) in GMAPI.commonHeaders where req.value(forHTTPHeaderField: k) == nil {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let (data, resp) = try await session.data(for: req)
        let http = resp as! HTTPURLResponse
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw OnStarError.notAuthenticated
        default:
            throw OnStarError.requestFailed(http.statusCode, String(decoding: data, as: UTF8.self))
        }
    }
}

/// Type-erased Encodable so we can pass heterogeneous command bodies.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
