import Foundation

/// Shared container identifiers so the app, the widget extension, and the
/// CarPlay scene all read/write the same cached vehicle snapshot and tokens.
enum AppGroup {
    static let identifier = "group.com.lightwave.zeus"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Keys used in the shared `UserDefaults` suite.
enum SharedKey {
    static let vehicleSnapshot = "zeus.vehicle.snapshot"
    static let selectedVIN     = "zeus.vehicle.selectedVIN"
    static let lastRefresh     = "zeus.vehicle.lastRefresh"
}
