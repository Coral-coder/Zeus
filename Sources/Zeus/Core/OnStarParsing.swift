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
        "EV RANGE",
        "ODOMETER",
        "TIRE PRESSURE",
        "AMBIENT AIR TEMPERATURE",
        "LAST TRIP DISTANCE"
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
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let vehicles = (root["vehicles"] as? [String: Any])?["vehicle"] as? [[String: Any]]
        else {
            throw OnStarError.decoding("Unexpected vehicles payload.")
        }
        return vehicles.compactMap { v in
            guard let vin = v["vin"] as? String else { return nil }
            let year = Int((v["year"] as? String) ?? "") ?? (v["year"] as? Int ?? 0)
            return Vehicle(
                vin: vin,
                make: (v["make"] as? String) ?? "Chevrolet",
                model: (v["model"] as? String) ?? "Bolt EV",
                year: year,
                nickname: v["nickname"] as? String
            )
        }
    }

    /// Map a diagnostics command payload into a `VehicleSnapshot`.
    static func parseSnapshot(_ data: Data, vin: String) throws -> VehicleSnapshot {
        let items = diagnosticElements(in: data)

        func value(_ name: String) -> Double? {
            items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
        }
        func string(_ name: String) -> String? {
            items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.message
        }

        let battery = (value("EV BATTERY LEVEL") ?? 0) / 100.0
        let plugState = string("EV PLUG STATE")?.lowercased() ?? ""
        let chargeState = string("EV CHARGE STATE")?.lowercased() ?? ""

        return VehicleSnapshot(
            vin: vin,
            batteryLevel: battery,
            rangeMiles: value("EV RANGE").map { Int($0) },
            isCharging: chargeState.contains("charging"),
            pluggedIn: plugState.contains("plug") || plugState.contains("connected"),
            minutesToFull: value("EV ESTIMATED CHARGE END").map { Int($0) },
            locked: true,
            climateOn: false,
            cabinTempF: value("AMBIENT AIR TEMPERATURE").map { Int($0 * 9/5 + 32) },
            odometerMiles: value("ODOMETER").map { Int($0) },
            tirePressureOK: nil,
            latitude: nil,
            longitude: nil,
            updatedAt: Date()
        )
    }

    private struct Element { let name: String; let value: Double?; let message: String? }

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
                let valStr = el["value"] as? String
                out.append(Element(name: name,
                                   value: valStr.flatMap(Double.init),
                                   message: el["message"] as? String ?? valStr))
            }
        }
        return out
    }
}
