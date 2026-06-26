import Foundation

/// Every remote command the app can issue. Raw values map to the OnStar/GM
/// mobile API command endpoints (`.../commands/{rawValue}`).
enum VehicleCommand: String, CaseIterable, Codable, Identifiable {
    case start            = "start"
    case cancelStart      = "cancelStart"
    case lock             = "lockDoor"
    case unlock           = "unlockDoor"
    case alert            = "alert"          // honk + flash (find my car)
    case cancelAlert      = "cancelAlert"
    case chargeOverride   = "chargeOverride"
    case getChargingProfile = "getChargingProfile"
    case setChargingProfile = "setChargingProfile"
    case diagnostics      = "diagnostics"
    case location         = "location"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:            return "Start"
        case .cancelStart:      return "Stop"
        case .lock:             return "Lock"
        case .unlock:           return "Unlock"
        case .alert:            return "Find Car"
        case .cancelAlert:      return "Stop Alert"
        case .chargeOverride:   return "Charge Now"
        case .getChargingProfile: return "Charge Profile"
        case .setChargingProfile: return "Set Charging"
        case .diagnostics:      return "Refresh"
        case .location:         return "Locate"
        }
    }

    var systemImage: String {
        switch self {
        case .start:            return "power"
        case .cancelStart:      return "stop.fill"
        case .lock:             return "lock.fill"
        case .unlock:           return "lock.open.fill"
        case .alert:            return "bell.and.waves.left.and.right.fill"
        case .cancelAlert:      return "bell.slash.fill"
        case .chargeOverride:   return "bolt.fill"
        case .getChargingProfile, .setChargingProfile: return "bolt.batteryblock.fill"
        case .diagnostics:      return "arrow.clockwise"
        case .location:         return "location.fill"
        }
    }

    /// Commands that should require Face ID / passcode confirmation.
    var requiresAuthentication: Bool {
        switch self {
        case .unlock, .start, .cancelStart: return true
        default: return false
        }
    }
}

/// Result of issuing a command.
struct CommandResult: Codable {
    enum Status: String, Codable { case success, inProgress, failed }
    var command: VehicleCommand
    var status: Status
    var message: String?
}
