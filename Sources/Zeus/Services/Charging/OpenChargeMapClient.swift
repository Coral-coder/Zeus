import Foundation
import CoreLocation

/// Fetches nearby charging stations from Open Charge Map (free, open data).
/// Get a key at https://openchargemap.org/site/profile/applications and put it
/// in `Secrets.plist` (OpenChargeMapKey) — see README.
struct OpenChargeMapClient {
    private let apiKey: String
    private let base = URL(string: "https://api.openchargemap.io/v3/poi")!

    init(apiKey: String = Secrets.openChargeMapKey) {
        self.apiKey = apiKey
    }

    /// Connection type ids OCM uses for CCS / fast DC (level 3). We tag anything
    /// at 25kW+ as DC fast, otherwise Level 2.
    func stations(near coordinate: CLLocationCoordinate2D,
                  radiusMiles: Double = 25,
                  fastOnly: Bool = false,
                  limit: Int = 60) async throws -> [ChargingStation] {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "key", value: apiKey),
            .init(name: "output", value: "json"),
            .init(name: "latitude", value: String(coordinate.latitude)),
            .init(name: "longitude", value: String(coordinate.longitude)),
            .init(name: "distance", value: String(radiusMiles)),
            .init(name: "distanceunit", value: "Miles"),
            .init(name: "maxresults", value: String(limit)),
            .init(name: "compact", value: "true"),
            .init(name: "verbose", value: "false"),
            .init(name: "countrycode", value: "US")
        ]
        if fastOnly { comps.queryItems?.append(.init(name: "levelid", value: "3")) }

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> [ChargingStation] {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return raw.compactMap { poi in
            guard
                let id = poi["ID"] as? Int,
                let address = poi["AddressInfo"] as? [String: Any],
                let lat = address["Latitude"] as? Double,
                let lon = address["Longitude"] as? Double
            else { return nil }

            let connections = poi["Connections"] as? [[String: Any]] ?? []
            let maxKW = connections.compactMap { $0["PowerKW"] as? Double }.max() ?? 0
            let speed: ChargingStation.Speed = maxKW >= 25 ? .level3 : (maxKW > 0 ? .level2 : .unknown)
            let statusType = poi["StatusType"] as? [String: Any]
            let operational = (statusType?["IsOperational"] as? Bool) ?? true
            let operatorInfo = poi["OperatorInfo"] as? [String: Any]

            return ChargingStation(
                id: id,
                name: (address["Title"] as? String) ?? "Charging Station",
                address: address["AddressLine1"] as? String,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                speed: speed,
                connectionCount: connections.count,
                network: operatorInfo?["Title"] as? String,
                isOperational: operational
            )
        }
    }
}
