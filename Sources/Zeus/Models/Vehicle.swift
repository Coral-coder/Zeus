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

/// A single labeled vehicle statistic, ready to display. Built from a GM
/// diagnostic element (or any other source) with a friendly label, formatted
/// value, and an SF Symbol. Stored in the snapshot so widgets/CarPlay can show
/// the full set without re-deriving it.
struct StatItem: Codable, Hashable, Identifiable {
    var label: String
    var value: String
    var systemImage: String
    /// An accent hint so the grid can color-code categories (battery, tires…).
    var accentHex: UInt32?
    var id: String { label }
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

    // Richer telemetry (all optional so older cached snapshots still decode).
    /// Current charger power, kW, when charging.
    var chargerPowerKw: Double?
    /// 12-volt accessory battery voltage.
    var voltage12V: Double?
    /// Per-corner tire pressures in PSI (keys: "LF","RF","LR","RR").
    var tirePressuresPSI: [String: Double]?
    /// The complete, display-ready list of everything GM reported.
    var stats: [StatItem]?

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
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            chargerPowerKw: nil,
            voltage12V: 12.6,
            tirePressuresPSI: ["LF": 35, "RF": 35, "LR": 34, "RR": 34],
            stats: [
                StatItem(label: "Battery", value: "72%", systemImage: "battery.75", accentHex: 0x3BFFB0),
                StatItem(label: "Range", value: "197 mi", systemImage: "road.lanes", accentHex: 0x2BE8FF),
                StatItem(label: "Odometer", value: "24,831 mi", systemImage: "gauge.with.dots.needle.bottom.50percent", accentHex: nil),
                StatItem(label: "Cabin Temp", value: "68°F", systemImage: "thermometer.medium", accentHex: 0xFFB23B),
                StatItem(label: "12V Battery", value: "12.6 V", systemImage: "minus.plus.batteryblock.fill", accentHex: nil),
                StatItem(label: "Tire LF", value: "35 psi", systemImage: "car.side.front.open.fill", accentHex: nil),
                StatItem(label: "Tire RF", value: "35 psi", systemImage: "car.side.front.open.fill", accentHex: nil),
                StatItem(label: "Tire LR", value: "34 psi", systemImage: "car.side.rear.open.fill", accentHex: nil),
                StatItem(label: "Tire RR", value: "34 psi", systemImage: "car.side.rear.open.fill", accentHex: nil)
            ]
        )
    }
}
