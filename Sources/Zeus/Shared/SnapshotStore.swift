import Foundation

/// Reads/writes the cached `VehicleSnapshot` in the shared App Group so the
/// main app, widgets, and CarPlay all show the same last-known state without
/// each needing to hit the network.
enum SnapshotStore {
    static func save(_ snapshot: VehicleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        AppGroup.defaults.set(data, forKey: SharedKey.vehicleSnapshot)
        AppGroup.defaults.set(Date(), forKey: SharedKey.lastRefresh)
    }

    static func load() -> VehicleSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: SharedKey.vehicleSnapshot) else { return nil }
        return try? JSONDecoder().decode(VehicleSnapshot.self, from: data)
    }

    static var lastRefresh: Date? {
        AppGroup.defaults.object(forKey: SharedKey.lastRefresh) as? Date
    }
}
