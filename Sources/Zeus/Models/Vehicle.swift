import Foundation

/// A Chevy Bolt (or Bolt EUV) on the account.
struct Vehicle: Identifiable, Codable, Hashable {
    var vin: String
    var make: String
    var model: String
    var year: Int
    var nickname: String?

    var id: String { vin }

    var displayName: String {
        nickname ?? "\(year) \(make) \(model)"
    }
}

/// A point-in-time snapshot of vehicle state, shown on the home screen, in
/// widgets, and on CarPlay. Cached in the shared App Group container.
struct VehicleSnapshot: Codable, Hashable {
    var vin: String
    /// 0...1 high-voltage battery state of charge.
    var batteryLevel: Double
    var rangeMiles: Int?
    var isCharging: Bool
    var pluggedIn: Bool
    /// Estimated minutes until full, when charging.
    var minutesToFull: Int?

    var locked: Bool
    var climateOn: Bool
    var cabinTempF: Int?

    var odometerMiles: Int?
    var tirePressureOK: Bool?

    var latitude: Double?
    var longitude: Double?

    var updatedAt: Date

    static func placeholder(vin: String = "1G1FZ6S0XK4100000") -> VehicleSnapshot {
        VehicleSnapshot(
            vin: vin,
            batteryLevel: 0.72,
            rangeMiles: 197,
            isCharging: false,
            pluggedIn: false,
            minutesToFull: nil,
            locked: true,
            climateOn: false,
            cabinTempF: 68,
            odometerMiles: 24831,
            tirePressureOK: true,
            latitude: 42.3314,
            longitude: -83.0458,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
