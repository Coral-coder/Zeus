import Foundation
import SwiftUI
import LocalAuthentication
import WidgetKit

/// The app's UI source of truth for vehicle state. Publishes state for SwiftUI,
/// gates sensitive commands behind biometrics, and delegates the actual network
/// work to the shared `RemoteCommandService` (which Siri and widgets also use).
@MainActor
final class VehicleManager: ObservableObject {
    static let shared = VehicleManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var vehicles: [Vehicle] = []
    @Published var selectedVehicle: Vehicle?
    @Published private(set) var snapshot: VehicleSnapshot?
    @Published private(set) var busyCommand: VehicleCommand?
    @Published var lastError: String?

    private let service = RemoteCommandService.shared
    private var config: OnStarConfig?

    private init() {
        self.config = KeychainStore.load(OnStarConfig.self, for: .onStarConfig)
        self.snapshot = SnapshotStore.load()
        Task { await bootstrap() }
    }

    var isConfigured: Bool { config != nil }

    // MARK: - Bootstrap & auth

    func bootstrap() async {
        isAuthenticated = await service.isAuthenticated
        if isAuthenticated {
            await loadVehicles()
            await refresh()
        }
    }

    func saveCommandPIN(_ pin: String) {
        guard var cfg = config else { return }
        cfg.commandPIN = pin
        try? KeychainStore.save(cfg, for: .onStarConfig)
        config = cfg
    }

    func signIn() async {
        // No fields to fill: ensure we have a config (just a device id) and then
        // hand off to GM's login. The VIN is read from the account afterwards.
        let cfg = config ?? OnStarConfig.makeNew(email: "", vin: "")
        if config == nil {
            try? KeychainStore.save(cfg, for: .onStarConfig)
            config = cfg
        }
        do {
            // Drive GM's B2C login on-device in Apple's real WebKit auth sheet
            // (clears Akamai's bot-wall), then persist the resulting token.
            let auth = GMAuthSession(config: cfg)
            try await service.signIn(using: { try await auth.authenticate() })
            isAuthenticated = true
            await loadVehicles()
            await refresh()
        } catch {
            present(error)
        }
    }

    func signOut() async {
        await service.signOut()
        isAuthenticated = false
        vehicles = []
        snapshot = nil
    }

    private func loadVehicles() async {
        do {
            let list = try await service.vehicles()
            self.vehicles = list
            if selectedVehicle == nil {
                selectedVehicle = list.first { $0.vin == config?.vin } ?? list.first
            }
            // Persist the chosen VIN so commands/widgets know which car to target.
            if let vin = selectedVehicle?.vin, config?.vin != vin {
                persistVIN(vin)
            }
        } catch {
            present(error)
        }
    }

    /// Store the active VIN in the config and the shared App Group.
    private func persistVIN(_ vin: String) {
        guard var cfg = config else { return }
        cfg.vin = vin
        try? KeychainStore.save(cfg, for: .onStarConfig)
        config = cfg
        AppGroup.defaults.set(vin, forKey: SharedKey.selectedVIN)
    }

    // MARK: - State refresh

    func refresh() async {
        do {
            let snap = try await service.refresh()
            self.snapshot = snap
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            present(error)
        }
    }

    // MARK: - Commands

    func perform(_ command: VehicleCommand) async {
        if command.requiresAuthentication {
            guard await authenticateBiometric(reason: "Confirm \(command.title)") else { return }
        }
        busyCommand = command
        defer { busyCommand = nil }
        do {
            _ = try await service.perform(command)
            // Reflect the optimistic/refreshed cache the service just wrote.
            self.snapshot = SnapshotStore.load()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            present(error)
        }
    }

    // MARK: - Helpers

    private func authenticateBiometric(reason: String) async -> Bool {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return await withCheckedContinuation { cont in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    private func present(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
