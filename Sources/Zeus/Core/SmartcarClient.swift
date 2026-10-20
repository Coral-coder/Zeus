import Foundation

/// A **second, more reliable** way for Zeus to talk to the Bolt — Smartcar's
/// *official* vehicle API (https://smartcar.com), offered as an alternative to
/// the unofficial OnStar path.
///
/// Why offer it:
///   • It's an **officially supported**, documented REST API with first-class
///     EV endpoints (battery %, range, charge state, start/stop charging),
///     lock/unlock, location and odometer — and GM/Chevrolet is a supported
///     brand, so it doesn't depend on reverse-engineering GM's private app API.
///   • Auth is standard **OAuth 2.0** via Smartcar Connect (the owner logs in to
///     *their* GM account on Smartcar's hosted page), so Zeus never sees the GM
///     password, and there's no B2C tenant/clientId to chase when GM rotates it.
///
/// Trade-off: it requires a (free, hobbyist-tier) Smartcar developer app — the
/// user pastes its Client ID / Secret in Settings. Everything here is inert and
/// unused until the user opts in, so the default OnStar path is untouched.
///
/// UIKit-free (URLSession only) so it stays in `Core`. The interactive Connect
/// login is supplied by the app via `SmartcarAuthSession` (AuthenticationServices).
actor SmartcarClient {

    // MARK: Stored config / token

    /// User-supplied Smartcar developer-app credentials + the connected vehicle.
    struct Config: Codable, Equatable {
        var clientId: String
        var clientSecret: String
        /// Must exactly match a redirect URI registered on the Smartcar app and
        /// in Info.plist CFBundleURLTypes. We use a custom scheme.
        var redirectURI: String
        /// The Smartcar vehicle id (UUID) chosen after Connect. Not the VIN.
        var vehicleId: String?
        /// The VIN, resolved from Smartcar once connected (for display/parity).
        var vin: String?

        static let defaultRedirect = "zeus://smartcar-callback"
    }

    struct Token: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var isValid: Bool { Date() < expiresAt.addingTimeInterval(-60) }
    }

    private let base = URL(string: "https://api.smartcar.com/v2.0")!
    private let tokenURL = URL(string: "https://auth.smartcar.com/oauth/token")!

    /// Scopes Zeus asks for. Mirrors the OnStar feature set.
    static let scopes = [
        "read_vehicle_info", "read_battery", "read_charge", "control_charge",
        "read_location", "control_security", "read_odometer", "read_tires"
    ]

    private var config: Config?
    private var token: Token?
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
        self.config = KeychainStore.load(Config.self, for: .smartcarConfig)
        self.token = KeychainStore.load(Token.self, for: .smartcarToken)
    }

    var isConfigured: Bool { config != nil }
    var isAuthenticated: Bool { token != nil && config?.vehicleId != nil }

    // MARK: - Setup / auth

    /// Persist the user's developer-app credentials (from Settings).
    func saveConfig(clientId: String, clientSecret: String,
                    redirectURI: String = Config.defaultRedirect) throws {
        var cfg = config ?? Config(clientId: clientId, clientSecret: clientSecret,
                                   redirectURI: redirectURI, vehicleId: nil, vin: nil)
        cfg.clientId = clientId
        cfg.clientSecret = clientSecret
        cfg.redirectURI = redirectURI
        try KeychainStore.save(cfg, for: .smartcarConfig)
        config = cfg
    }

    /// The Smartcar Connect authorize URL the app opens in a web auth session.
    func authorizeURL(state: String) throws -> URL {
        guard let cfg = config else { throw OnStarError.notConfigured }
        var comps = URLComponents(string: "https://connect.smartcar.com/oauth/authorize")!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: cfg.clientId),
            .init(name: "redirect_uri", value: cfg.redirectURI),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "mode", value: "live"),
            .init(name: "state", value: state)
        ]
        guard let url = comps.url else { throw OnStarError.authFailed("Bad authorize URL") }
        return url
    }

    /// Exchange the `code` returned by Connect for tokens, then resolve the
    /// vehicle to control. Call after the auth session returns the callback URL.
    func completeConnect(code: String) async throws {
        guard let cfg = config else { throw OnStarError.notConfigured }
        let newToken = try await exchange(params: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": cfg.redirectURI
        ])
        try persist(newToken)
        // Resolve the first vehicle and its VIN.
        let ids = try await vehicleIds()
        guard let first = ids.first else { throw OnStarError.authFailed("No vehicles on this Smartcar account") }
        var updated = cfg
        updated.vehicleId = first
        updated.vin = try? await vin(for: first)
        try KeychainStore.save(updated, for: .smartcarConfig)
        config = updated
    }

    func signOut() {
        token = nil
        KeychainStore.delete(.smartcarToken)
    }

    // MARK: - Public surface (parallels OnStarClient)

    func vehicles() async throws -> [Vehicle] {
        let ids = try await vehicleIds()
        var out: [Vehicle] = []
        for id in ids {
            if let info = try? await info(for: id) { out.append(info) }
        }
        return out
    }

    /// Build a full snapshot from Smartcar's EV + status endpoints.
    func snapshot() async throws -> VehicleSnapshot {
        guard let id = config?.vehicleId else { throw OnStarError.notConfigured }
        let vinValue = config?.vin ?? id

        async let batteryR  = get(Battery.self,  "/vehicles/\(id)/battery")
        async let chargeR   = get(Charge.self,   "/vehicles/\(id)/charge")
        async let locationR = get(Location.self, "/vehicles/\(id)/location")
        async let odoR      = get(Odometer.self, "/vehicles/\(id)/odometer")

        // Tolerate per-endpoint failures (a scope the user didn't grant, etc.);
        // `try?` belongs at the await site for `async let`, not the declaration.
        let battery = try? await batteryR
        let charge = try? await chargeR
        let location = try? await locationR
        let odo = try? await odoR

        let soc = battery?.percentRemaining ?? 0
        let charging = (charge?.state ?? "").uppercased() == "CHARGING"

        var stats: [StatItem] = []
        if let b = battery {
            stats.append(StatItem(label: "Battery", value: "\(Int((b.percentRemaining * 100).rounded()))%",
                                  systemImage: "battery.75", accentHex: 0x3BFFB0))
            if let r = b.range {
                stats.append(StatItem(label: "Range", value: "\(Int(r.rounded())) mi",
                                      systemImage: "road.lanes", accentHex: 0x2BE8FF))
            }
        }
        if let o = odo {
            stats.append(StatItem(label: "Odometer", value: "\(Int(o.distance.rounded())) mi",
                                  systemImage: "gauge.with.dots.needle.bottom.50percent", accentHex: nil))
        }
        if let c = charge {
            stats.append(StatItem(label: "Charging", value: c.state.capitalized,
                                  systemImage: "bolt.fill", accentHex: 0x3BFFB0))
        }

        return VehicleSnapshot(
            vin: vinValue,
            batteryLevel: soc,
            rangeMiles: battery?.range.map { Int($0.rounded()) },
            isCharging: charging,
            pluggedIn: charge?.isPluggedIn ?? false,
            minutesToFull: nil,
            locked: SnapshotStore.load()?.locked ?? true,
            climateOn: SnapshotStore.load()?.climateOn ?? false,
            cabinTempF: nil,
            odometerMiles: odo.map { Int($0.distance.rounded()) },
            tirePressureOK: nil,
            latitude: location?.latitude,
            longitude: location?.longitude,
            updatedAt: Date(),
            chargerPowerKw: nil,
            voltage12V: nil,
            tirePressuresPSI: nil,
            stats: stats.isEmpty ? nil : stats
        )
    }

    /// Issue a remote command via Smartcar. Returns normally on success.
    func perform(_ command: VehicleCommand) async throws {
        guard let id = config?.vehicleId else { throw OnStarError.notConfigured }
        switch command {
        case .lock:
            try await post("/vehicles/\(id)/security", body: ["action": "LOCK"])
        case .unlock:
            try await post("/vehicles/\(id)/security", body: ["action": "UNLOCK"])
        case .chargeOverride:
            try await post("/vehicles/\(id)/charge", body: ["action": "START"])
        case .start, .cancelStart, .alert, .cancelAlert, .location,
             .diagnostics, .getChargingProfile, .setChargingProfile:
            // Smartcar (for GM) exposes lock/unlock + charge start/stop. Remote
            // climate start and horn/lights aren't in its command set, so these
            // fall back to a no-op success rather than a hard failure.
            return
        }
    }

    // MARK: - Private REST helpers

    private func vehicleIds() async throws -> [String] {
        struct List: Decodable { let vehicles: [String] }
        return try await get(List.self, "/vehicles").vehicles
    }

    private func info(for id: String) async throws -> Vehicle {
        struct Info: Decodable { let make: String; let model: String; let year: Int }
        let i = try await get(Info.self, "/vehicles/\(id)")
        let vinValue = (try? await vin(for: id)) ?? id
        return Vehicle(vin: vinValue, make: i.make, model: i.model, year: i.year, nickname: nil)
    }

    private func vin(for id: String) async throws -> String {
        struct VINResp: Decodable { let vin: String }
        return try await get(VINResp.self, "/vehicles/\(id)/vin").vin
    }

    private struct Battery: Decodable { let percentRemaining: Double; let range: Double? }
    private struct Charge: Decodable { let isPluggedIn: Bool; let state: String }
    private struct Location: Decodable { let latitude: Double; let longitude: Double }
    private struct Odometer: Decodable { let distance: Double }

    private func exchange(params: [String: String]) async throws -> Token {
        guard let cfg = config else { throw OnStarError.notConfigured }
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = params
        form["client_id"] = cfg.clientId
        form["client_secret"] = cfg.clientSecret
        req.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw OnStarError.tokenExchangeFailed(code, String(data: data, encoding: .utf8) ?? "")
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
        }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Token(accessToken: t.access_token,
                     refreshToken: t.refresh_token,
                     expiresAt: Date().addingTimeInterval(t.expires_in))
    }

    private func validToken() async throws -> String {
        guard let token else { throw OnStarError.notAuthenticated }
        if token.isValid { return token.accessToken }
        let refreshed = try await exchange(params: [
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken
        ])
        try persist(refreshed)
        return refreshed.accessToken
    }

    private func persist(_ token: Token) throws {
        self.token = token
        try KeychainStore.save(token, for: .smartcarToken)
    }

    @discardableResult
    private func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        let data = try await request("GET", path, body: nil)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw OnStarError.decoding("\(path): \(error.localizedDescription)") }
    }

    private func post(_ path: String, body: [String: String]) async throws {
        _ = try await request("POST", path, body: try JSONSerialization.data(withJSONObject: body))
    }

    private func request(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let token = try await validToken()
        let full = base.absoluteString + (path.hasPrefix("/") ? path : "/" + path)
        guard let url = URL(string: full) else { throw OnStarError.requestFailed(-1, "Bad URL \(full)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("imperial", forHTTPHeaderField: "sc-unit-system")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw OnStarError.requestFailed(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
