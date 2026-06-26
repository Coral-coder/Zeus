import Foundation

// MARK: - Command bodies

/// Body for the diagnostics command — the set of telemetry items to fetch.
struct DiagnosticsRequest: Encodable {
    let diagnosticsRequest: Inner
    struct Inner: Encodable { let diagnosticItem: [String] }

    static let full = DiagnosticsRequest(diagnosticsRequest: .init(diagnosticItem: [
        "EV BATTERY LEVEL",
        "EV ESTIMATED CHARGE END",
        "EV PLUG STATE",
        "EV CHARGE STATE",
        "EV PLUG VOLTAGE",
        "EV RANGE",
        "CHARGER POWER LEVEL",
        "ODOMETER",
        "TIRE PRESSURE",
        "AMBIENT AIR TEMPERATURE",
        "LAST TRIP DISTANCE",
        "LAST TRIP FUEL ECONOMY",
        "ENERGY EFFICIENCY",
        "LIFETIME ENERGY USED",
        "VEHICLE RANGE",
        "INTERM VOLT BATT VOLT"
    ]))
}

/// Body for remote start — preconditioning the cabin.
struct StartRequest: Encodable {
    var cabinTemperatureF: Int? = nil
}

/// Body for charge override (e.g. start charging immediately).
struct ChargeOverrideRequest: Encodable {
    enum Mode: String, Encodable { case chargeNow = "CHARGE_NOW", cancelOverride = "CANCEL_OVERRIDE" }
    let chargeOverride: Mode
}

// MARK: - Command polling

enum CommandPoll {
    enum Outcome {
        case success(Data)
        case inProgress
        case failed(String)
    }

    /// The follow-up poll URL inside a command response, if the command is async.
    static func statusURL(from data: Data) -> URL? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let cr = root["commandResponse"] as? [String: Any]
        else { return nil }

        if let status = cr["status"] as? String,
           status.lowercased() != "inprogress" {
            return nil
        }
        if let urlString = cr["url"] as? String { return URL(string: urlString) }
        return nil
    }

    static func outcome(from data: Data) -> Outcome {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let cr = root["commandResponse"] as? [String: Any],
            let status = (cr["status"] as? String)?.lowercased()
        else {
            return .success(data)
        }

        switch status {
        case "success", "connectionsuccess":
            return .success(data)
        case "inprogress":
            return .inProgress
        default:
            let msg = (cr["type"] as? String) ?? status
            return .failed(msg)
        }
    }
}

// MARK: - Response parsing

enum VehicleResponseParser {

    static func parseVehicles(_ data: Data) throws -> [Vehicle] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OnStarError.decoding("Vehicles: " + snippet(data))
        }
        // New GraphQL garage shape: { data: { vehicles: [ … ] } }.
        // Legacy shape: { vehicles: { vehicle: [ … ] } }.
        let list = ((root["data"] as? [String: Any])?["vehicles"] as? [[String: Any]])
            ?? ((root["vehicles"] as? [String: Any])?["vehicle"] as? [[String: Any]])
            ?? (root["vehicles"] as? [[String: Any]])
            ?? []

        let vehicles = list.compactMap { v -> Vehicle? in
            guard let vin = v["vin"] as? String, !vin.isEmpty else { return nil }
            let year: Int = (v["year"] as? Int)
                ?? Int((v["year"] as? String) ?? "")
                ?? 0
            return Vehicle(
                vin: vin,
                make: (v["make"] as? String) ?? "Chevrolet",
                model: (v["model"] as? String) ?? "Bolt EV",
                year: year,
                nickname: (v["nickName"] as? String) ?? (v["nickname"] as? String)
            )
        }

        if vehicles.isEmpty {
            if let errors = root["errors"] as? [[String: Any]],
               let msg = errors.first?["message"] as? String {
                throw OnStarError.decoding("Vehicles: \(msg)")
            }
            throw OnStarError.decoding("No vehicles on the account.")
        }
        return vehicles
    }

    /// Parse GM's vehicle health-status payload into a `VehicleSnapshot`. The
    /// response is a tree of `diagnostics[]`, each optionally carrying a value
    /// and nested `diagnosticElements[]` (e.g. the four tire pressures).
    static func parseHealthStatus(_ data: Data, vin: String) throws -> VehicleSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw OnStarError.decoding("Health: " + snippet(data))
        }
        var items: [Element] = []
        func ingest(_ d: [String: Any]) {
            let name = (d["displayName"] as? String) ?? (d["name"] as? String) ?? ""
            guard !name.isEmpty else { return }
            let valAny = d["value"]
            let valStr = (valAny as? String) ?? (valAny as? NSNumber)?.stringValue
            let unit = (d["uom"] as? String) ?? (d["unit"] as? String)
            let status = (d["message"] as? String) ?? (d["status"] as? String)
            // Only keep entries that carry a value or a meaningful status.
            if valStr != nil || (status != nil && status?.isEmpty == false) {
                items.append(Element(name: name,
                                     value: valStr.flatMap { Double($0) },
                                     unit: unit,
                                     message: status,
                                     rawValue: valStr))
            }
        }
        let diagnostics = (root["diagnostics"] as? [[String: Any]]) ?? []
        for diag in diagnostics {
            ingest(diag)
            for el in (diag["diagnosticElements"] as? [[String: Any]]) ?? [] { ingest(el) }
        }
        return makeSnapshot(from: items, vin: vin)
    }

    /// Map a (legacy) diagnostics command payload into a `VehicleSnapshot`.
    static func parseSnapshot(_ data: Data, vin: String) throws -> VehicleSnapshot {
        return makeSnapshot(from: diagnosticElements(in: data), vin: vin)
    }

    /// Shared mapping: turn a flat list of diagnostic elements into a snapshot.
    /// Matching is keyword-based and unit-aware so it works across both the
    /// legacy command payload and the health-status tree, in metric or US units.
    private static func makeSnapshot(from items: [Element], vin: String) -> VehicleSnapshot {
        // First element whose name contains all the given keywords.
        func find(_ keywords: [String]) -> Element? {
            items.first { e in
                let n = e.name.uppercased()
                return keywords.allSatisfy { n.contains($0) }
            }
        }
        func firstFind(_ groups: [[String]]) -> Element? {
            for g in groups { if let e = find(g) { return e } }
            return nil
        }
        func text(_ e: Element?) -> String { (e?.message ?? e?.rawValue ?? "").lowercased() }
        func miles(_ e: Element?) -> Int? {
            guard let v = e?.value else { return nil }
            let u = (e?.unit ?? "").uppercased()
            return u.contains("KM") ? Int((v * 0.621371).rounded()) : Int(v.rounded())
        }

        // Battery %: value is 0–100 (sometimes 0–1).
        let batteryRaw = firstFind([["BATTERY", "LEVEL"], ["STATE", "CHARGE"], ["SOC"], ["BATTERY"]])?.value ?? 0
        let battery = batteryRaw > 1 ? batteryRaw / 100.0 : batteryRaw

        let plugState = text(firstFind([["PLUG"], ["CONNECTOR"]]))
        let chargeState = text(firstFind([["CHARGE", "STATE"], ["CHARGING", "STATUS"], ["CHARGING"]]))

        // Per-corner tire pressures, unit-aware (kPa / bar / psi).
        var tires: [String: Double] = [:]
        for (corner, names) in Self.tireCorners {
            if let e = items.first(where: { Self.matchesTire($0.name, names) }), let v = e.value {
                let u = (e.unit ?? "").uppercased()
                if u.contains("KPA") { tires[corner] = (v * 0.1450377).rounded() }
                else if u.contains("BAR") { tires[corner] = (v * 14.5038).rounded() }
                else { tires[corner] = v.rounded() }   // assume psi
            }
        }
        let tirePressureOK: Bool? = tires.isEmpty ? nil : tires.values.allSatisfy { $0 >= 30 && $0 <= 42 }

        // Ambient temperature, unit-aware.
        let cabinF: Int? = {
            guard let e = firstFind([["AMBIENT"], ["CABIN", "TEMP"], ["OUTSIDE", "TEMP"]]),
                  let v = e.value else { return nil }
            let u = (e.unit ?? "").uppercased()
            return u.contains("F") ? Int(v.rounded()) : Int((v * 9/5 + 32).rounded())
        }()

        let rangeMiles = miles(firstFind([["EV", "RANGE"], ["ELECTRIC", "RANGE"], ["RANGE"]]))
        let odometerMiles = miles(find(["ODOMETER"]))

        // Build the full display-ready stat list from everything GM returned,
        // excluding tire elements (we synthesize nicer per-corner cards below).
        var stats = items
            .filter { !($0.name.uppercased().contains("TIRE") && $0.name.uppercased().contains("PRESSURE")) }
            .compactMap { $0.statItem }
        // Synthesize a couple of friendly cards from typed fields if present.
        if !tires.isEmpty {
            for corner in ["LF", "RF", "LR", "RR"] where tires[corner] != nil {
                let icon = corner.hasPrefix("L") ? "car.side.front.open.fill" : "car.side.rear.open.fill"
                stats.append(StatItem(label: "Tire \(corner)",
                                      value: "\(Int(tires[corner]!)) psi",
                                      systemImage: icon, accentHex: nil))
            }
        }

        return VehicleSnapshot(
            vin: vin,
            batteryLevel: battery,
            rangeMiles: rangeMiles,
            isCharging: chargeState.contains("charging") || chargeState.contains("active"),
            pluggedIn: plugState.contains("plug") || plugState.contains("connected") || plugState.contains("in"),
            minutesToFull: firstFind([["CHARGE", "END"], ["TIME", "FULL"]])?.value.map { Int($0) },
            locked: true,
            climateOn: false,
            cabinTempF: cabinF,
            odometerMiles: odometerMiles,
            tirePressureOK: tirePressureOK,
            latitude: nil,
            longitude: nil,
            updatedAt: Date(),
            chargerPowerKw: find(["CHARGER", "POWER"])?.value,
            voltage12V: firstFind([["12", "VOLT"], ["INTERM", "VOLT"], ["ACCESSORY", "VOLT"]])?.value,
            tirePressuresPSI: tires.isEmpty ? nil : tires,
            stats: stats.isEmpty ? nil : stats
        )
    }

    // MARK: - Element model

    private struct Element {
        let name: String
        let value: Double?
        let unit: String?
        let message: String?
        let rawValue: String?

        /// A friendly, display-ready stat (or nil for things not worth showing).
        var statItem: StatItem? {
            let label = VehicleResponseParser.humanLabel(name)
            guard let display = VehicleResponseParser.displayValue(value: value, unit: unit,
                                                                   message: message, raw: rawValue)
            else { return nil }
            let (icon, accent) = VehicleResponseParser.iconAndAccent(for: name)
            return StatItem(label: label, value: display, systemImage: icon, accentHex: accent)
        }
    }

    private static func diagnosticElements(in data: Data) -> [Element] {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }

        let cr = root["commandResponse"] as? [String: Any]
        let body = cr?["body"] as? [String: Any]
        let responses = body?["diagnosticResponse"] as? [[String: Any]] ?? []

        var out: [Element] = []
        for resp in responses {
            let elements = resp["diagnosticElement"] as? [[String: Any]] ?? []
            for el in elements {
                let name = (el["name"] as? String) ?? ""
                guard !name.isEmpty else { continue }
                let valStr = el["value"] as? String
                out.append(Element(name: name,
                                   value: valStr.flatMap { Double($0) },
                                   unit: el["unit"] as? String,
                                   message: el["message"] as? String,
                                   rawValue: valStr))
            }
        }
        return out
    }

    // MARK: - Formatting

    private static let tireCorners: [(String, [String])] = [
        ("LF", ["LF", "LEFT FRONT", "FRONT LEFT"]),
        ("RF", ["RF", "RIGHT FRONT", "FRONT RIGHT"]),
        ("LR", ["LR", "LEFT REAR", "REAR LEFT"]),
        ("RR", ["RR", "RIGHT REAR", "REAR RIGHT"])
    ]

    private static func matchesTire(_ name: String, _ keys: [String]) -> Bool {
        let n = name.uppercased()
        return n.contains("TIRE") && n.contains("PRESSURE") && keys.contains { n.contains($0) }
    }

    /// Title-case a GM ALL-CAPS diagnostic name into something readable.
    static func humanLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
            .replacingOccurrences(of: "ev ", with: "EV ")
            .replacingOccurrences(of: "interm volt batt volt", with: "12V Battery")
        return lower
            .split(separator: " ")
            .map { word -> String in
                let w = String(word)
                if w == "EV" { return "EV" }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Convert a value+unit (or textual message) into a US-friendly string.
    static func displayValue(value: Double?, unit: String?, message: String?, raw: String?) -> String? {
        let u = (unit ?? "").uppercased()

        if let v = value {
            switch u {
            case "PERCENT", "%":
                return "\(Int(v.rounded()))%"
            case "KM":
                return "\(Int((v * 0.621371).rounded())) mi"
            case "KILOMETERS":
                return "\(Int((v * 0.621371).rounded())) mi"
            case "KPA":
                return "\(Int((v * 0.1450377).rounded())) psi"
            case "CELSIUS", "C", "DEG C", "°C":
                return "\(Int((v * 9/5 + 32).rounded()))°F"
            case "VOLTS", "V":
                return String(format: "%.1f V", v)
            case "KW":
                return String(format: "%.1f kW", v)
            case "KWH":
                return String(format: "%.1f kWh", v)
            case "KM/L(E)", "KM/KWH", "KWH/100KM":
                return String(format: "%.1f %@", v, unit ?? "")
            case "MINUTES", "MIN":
                return "\(Int(v)) min"
            case "":
                // No unit: integers as-is, fractions to 1 dp.
                return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
            default:
                let num = v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
                return "\(num) \(unit ?? "")"
            }
        }

        // No numeric value — fall back to the textual status, prettified.
        if let m = (message ?? raw)?.trimmingCharacters(in: .whitespaces), !m.isEmpty,
           m.uppercased() != "NO DATA", m.uppercased() != "INVALID" {
            return m.capitalized
        }
        return nil
    }

    /// Pick an SF Symbol + accent for a known diagnostic name.
    static func iconAndAccent(for name: String) -> (String, UInt32?) {
        let n = name.uppercased()
        switch true {
        case n.contains("BATTERY LEVEL"):              return ("battery.75", 0x3BFFB0)
        case n.contains("RANGE"):                      return ("road.lanes", 0x2BE8FF)
        case n.contains("CHARGE END") || n.contains("CHARGE START"): return ("clock.fill", 0x2BE8FF)
        case n.contains("CHARGER POWER"):              return ("bolt.fill", 0xFFB23B)
        case n.contains("CHARGE STATE"):               return ("bolt.batteryblock.fill", 0x3BFFB0)
        case n.contains("PLUG"):                       return ("powerplug.fill", 0x3BFFB0)
        case n.contains("ODOMETER"):                   return ("gauge.with.dots.needle.bottom.50percent", nil)
        case n.contains("TIRE"):                       return ("car.side.rear.open.fill", nil)
        case n.contains("AIR TEMPERATURE") || n.contains("TEMP"): return ("thermometer.medium", 0xFFB23B)
        case n.contains("TRIP"):                       return ("point.topleft.down.curvedto.point.bottomright.up", 0x9B5BFF)
        case n.contains("EFFICIENCY"):                 return ("leaf.fill", 0x3BFFB0)
        case n.contains("ENERGY"):                     return ("bolt.square.fill", 0xFFB23B)
        case n.contains("VOLT"):                       return ("minus.plus.batteryblock.fill", nil)
        case n.contains("OIL"):                        return ("oilcan.fill", 0xFFB23B)
        default:                                       return ("gauge.with.dots.needle.bottom.50percent", nil)
        }
    }
}
