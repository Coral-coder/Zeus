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

    /// The charging network/operator, normalized for filtering & coloring.
    enum Network: String, CaseIterable {
        case tesla = "Tesla"
        case chargePoint = "ChargePoint"
        case evgo = "EVgo"
        case electrifyAmerica = "Electrify America"
        case other = "Other"

        static func from(_ raw: String?) -> Network {
            let s = (raw ?? "").lowercased()
            if s.contains("tesla") { return .tesla }
            if s.contains("chargepoint") || s.contains("charge point") { return .chargePoint }
            if s.contains("evgo") || s.contains("ev go") { return .evgo }
            if s.contains("electrify") { return .electrifyAmerica }
            return .other
        }
    }

    let id: Int
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let speed: Speed
    let kw: Double
    let connectionCount: Int
    let network: String?
    let isOperational: Bool

    var networkKind: Network { Network.from(network) }
    var isTesla: Bool { networkKind == .tesla }

    func distance(from origin: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
    }

    static func == (lhs: ChargingStation, rhs: ChargingStation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
