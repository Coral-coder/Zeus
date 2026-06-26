import Foundation
import CoreLocation

/// A public charging station, normalized from Open Charge Map.
struct ChargingStation: Identifiable, Hashable {
    enum Speed: String {
        case level2 = "Level 2"
        case level3 = "DC Fast"
        case unknown = "Charger"

        var maxKW: String {
            switch self {
            case .level2: return "≤ 19 kW"
            case .level3: return "50–350 kW"
            case .unknown: return ""
            }
        }
    }

    let id: Int
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let speed: Speed
    let connectionCount: Int
    let network: String?
    let isOperational: Bool

    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
    }

    static func == (lhs: ChargingStation, rhs: ChargingStation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
