import Foundation

/// UIKit-free façade over `OnStarClient` shared by the app, App Intents (Siri),
/// and widgets. Resolves the current VIN from the saved config, runs commands
/// headlessly, and keeps the shared snapshot cache current so widgets refresh.
///
/// The app drives interactive sign-in through `signIn(using:)`; everything else
/// (commands, refresh) works without UI in any process that holds a valid token.
actor RemoteCommandService {
    static let shared = RemoteCommandService()

    private let client = OnStarClient()
    private let smartcar = SmartcarClient()

    private var vin: String? {
        KeychainStore.load(OnStarConfig.self, for: .onStarConfig)?.vin
            ?? AppGroup.defaults.string(forKey: SharedKey.selectedVIN)
    }

    var isAuthenticated: Bool {
        get async {
            if ConnectionBackend.current == .smartcar { return await smartcar.isAuthenticated }
            return await client.isAuthenticated
        }
    }

    // MARK: - Auth

    func signIn(using provider: () async throws -> GMToken) async throws {
        try await client.login(using: provider)
    }

    func signOut() async {
        await client.signOut()
        await smartcar.signOut()
    }

    // MARK: - Smartcar (official-API alternative)

    /// Step 1 of Smartcar Connect: store the dev-app credentials and return the
    /// hosted-login URL the app should present in `SmartcarAuthSession`.
    func smartcarAuthorizeURL(clientId: String, clientSecret: String, redirect: String) async throws -> URL {
        try await smartcar.saveConfig(clientId: clientId, clientSecret: clientSecret, redirectURI: redirect)
        return try await smartcar.authorizeURL(state: UUID().uuidString)
    }

    /// Step 2: exchange the captured auth `code` for tokens and make Smartcar the
    /// active backend.
    func smartcarComplete(code: String) async throws {
        try await smartcar.completeConnect(code: code)
        ConnectionBackend.current = .smartcar
    }

    // MARK: - Commands

    /// Run a command and (best-effort) update the cached snapshot so the UI and
    /// widgets reflect the new state immediately.
    @discardableResult
    func perform(_ command: VehicleCommand) async throws -> CommandResult {
        if ConnectionBackend.current == .smartcar {
            try await smartcar.perform(command)
            applyOptimistic(command)
            return CommandResult(command: command, status: .success, message: nil)
        }
        guard let vin else { throw OnStarError.notConfigured }
        switch command {
        case .start:
            try await client.runCommand(.start, vin: vin, body: StartRequest())
        case .chargeOverride:
            try await client.runCommand(.chargeOverride, vin: vin,
                                        body: ChargeOverrideRequest(chargeOverride: .chargeNow))
        case .diagnostics:
            let snap = try await client.diagnostics(vin: vin)
            mergeAndCache(snap)
            return CommandResult(command: command, status: .success, message: nil)
        default:
            try await client.runCommand(command, vin: vin)
        }
        applyOptimistic(command)
        return CommandResult(command: command, status: .success, message: nil)
    }

    /// Pull fresh diagnostics and cache them.
    @discardableResult
    func refresh() async throws -> VehicleSnapshot {
        if ConnectionBackend.current == .smartcar {
            return mergeAndCache(try await smartcar.snapshot())
        }
        guard let vin else { throw OnStarError.notConfigured }
        let snap = try await client.diagnostics(vin: vin)
        return mergeAndCache(snap)
    }

    func vehicles() async throws -> [Vehicle] {
        if ConnectionBackend.current == .smartcar { return try await smartcar.vehicles() }
        return try await client.vehicles()
    }

    // MARK: - Snapshot cache

    @discardableResult
    private func mergeAndCache(_ snap: VehicleSnapshot) -> VehicleSnapshot {
        var merged = snap
        if let prev = SnapshotStore.load() {
            merged.locked = prev.locked
            merged.climateOn = prev.climateOn
        }
        SnapshotStore.save(merged)
        return merged
    }

    private func applyOptimistic(_ command: VehicleCommand) {
        guard var snap = SnapshotStore.load() else { return }
        switch command {
        case .lock:           snap.locked = true
        case .unlock:         snap.locked = false
        case .start:          snap.climateOn = true
        case .cancelStart:    snap.climateOn = false
        case .chargeOverride: snap.isCharging = true
        default: break
        }
        snap.updatedAt = Date()
        SnapshotStore.save(snap)
    }
}
