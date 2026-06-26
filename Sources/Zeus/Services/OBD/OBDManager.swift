import Foundation
import CoreBluetooth

/// A single live parameter read from the car.
struct OBDReading: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let unit: String
    var formatted: String { String(format: "%.0f %@", value, unit) }
}

/// Connects to a Bluetooth LE ELM327-style OBD-II dongle, polls a set of PIDs,
/// and publishes live readings. The Bolt exposes standard OBD-II PIDs plus
/// manufacturer EV PIDs; here we read the universal ones (speed, RPM-equiv,
/// coolant/battery temp, control module voltage) and expose hooks for the
/// GM-specific high-voltage battery PIDs.
@MainActor
final class OBDManager: NSObject, ObservableObject {
    static let shared = OBDManager()

    @Published private(set) var isConnected = false
    @Published private(set) var readings: [String: OBDReading] = [:]

    /// Readings suitable for the CarPlay dashboard, ordered.
    var latestReadable: [OBDReading] {
        Self.pollPlan.compactMap { readings[$0.command] }
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var buffer = ""
    private var pollIndex = 0

    // Common ELM327 BLE service/characteristics vary by clone; these cover the
    // widespread "VLinker / Vgate" UUIDs. Adjust for your adapter if needed.
    private let serviceUUID = CBUUID(string: "FFF0")
    private let writeUUID   = CBUUID(string: "FFF2")
    private let notifyUUID  = CBUUID(string: "FFF1")

    /// PIDs to poll in a loop. `command` is the OBD service-01 PID hex.
    struct PID { let command: String; let label: String; let unit: String; let decode: ([Int]) -> Double }
    static let pollPlan: [PID] = [
        PID(command: "010D", label: "Speed", unit: "km/h") { bytes in Double(bytes.first ?? 0) },
        PID(command: "010C", label: "RPM", unit: "rpm") { b in (Double(b[0]) * 256 + Double(b[1])) / 4 },
        PID(command: "0105", label: "Coolant", unit: "°C") { b in Double(b[0]) - 40 },
        PID(command: "0142", label: "Module V", unit: "V") { b in (Double(b[0]) * 256 + Double(b[1])) / 1000 },
        PID(command: "015B", label: "HV Battery", unit: "%") { b in Double(b[0]) * 100 / 255 }
    ]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func connect() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    // MARK: - Polling

    private func sendNextPID() {
        guard let peripheral, let writeChar, !Self.pollPlan.isEmpty else { return }
        let pid = Self.pollPlan[pollIndex % Self.pollPlan.count]
        pollIndex += 1
        let cmd = pid.command + "\r"
        peripheral.writeValue(Data(cmd.utf8), for: writeChar, type: .withoutResponse)
    }

    private func handleLine(_ line: String, for pid: PID) {
        // Response like "41 0D 1A" -> drop the "41" + PID echo, decode the rest.
        let hex = line.replacingOccurrences(of: " ", with: "").uppercased()
        guard hex.hasPrefix("41") else { return }
        let payload = Array(hex.dropFirst(4)) // drop "41" + 2-char PID
        var bytes: [Int] = []
        var i = payload.startIndex
        while i < payload.endIndex {
            let next = payload.index(i, offsetBy: 2, limitedBy: payload.endIndex) ?? payload.endIndex
            if let b = Int(String(payload[i..<next]), radix: 16) { bytes.append(b) }
            i = next
        }
        guard !bytes.isEmpty else { return }
        let reading = OBDReading(label: pid.label, value: pid.decode(bytes), unit: pid.unit)
        readings[pid.command] = reading
    }
}

extension OBDManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in if central.state == .poweredOn { connect() } }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            self.peripheral = peripheral
            peripheral.delegate = self
            central.stopScan()
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.isConnected = false }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                if char.uuid == writeUUID { writeChar = char }
                if char.uuid == notifyUUID {
                    notifyChar = char
                    peripheral.setNotifyValue(true, for: char)
                }
            }
            // Init ELM327 then begin polling.
            if let writeChar {
                ["ATZ\r", "ATE0\r", "ATSP0\r"].forEach {
                    peripheral.writeValue(Data($0.utf8), for: writeChar, type: .withoutResponse)
                }
                sendNextPID()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let text = String(data: data, encoding: .ascii) else { return }
        Task { @MainActor in
            buffer += text
            guard buffer.contains(">") || buffer.contains("\r") else { return }
            let lines = buffer.split(whereSeparator: { $0 == "\r" || $0 == ">" })
            let lastPID = Self.pollPlan[(pollIndex - 1 + Self.pollPlan.count) % Self.pollPlan.count]
            for line in lines { handleLine(String(line), for: lastPID) }
            buffer = ""
            sendNextPID()
        }
    }
}
