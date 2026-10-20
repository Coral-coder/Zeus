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
    static let backend         = "zeus.connection.backend"
}

/// Which API Zeus uses to reach the car. OnStar (the unofficial GM mobile API)
/// is the default; Smartcar is the official-API alternative the user can opt in
/// to in Settings. Stored in the shared suite so the app, Siri and widgets agree.
enum ConnectionBackend: String {
    case onStar
    case smartcar

    static var current: ConnectionBackend {
        get { ConnectionBackend(rawValue: AppGroup.defaults.string(forKey: SharedKey.backend) ?? "") ?? .onStar }
        set { AppGroup.defaults.set(newValue.rawValue, forKey: SharedKey.backend) }
    }

    var displayName: String {
        switch self {
        case .onStar:   return "OnStar (myChevrolet)"
        case .smartcar: return "Smartcar (official API)"
        }
    }
}
