import Foundation
import CoreBluetooth

/// A single live parameter read from the car.
struct OBDReading: Identifiable {
    let id = UUID()
    let command: String
    let label: String
    let value: Double
    let unit: String
    var systemImage: String = "gauge.with.dots.needle.bottom.50percent"
    var formatted: String {
        let num: String
        if value == value.rounded() { num = "\(Int(value))" }
        else if abs(value) < 10 { num = String(format: "%.3f", value) }   // cell volts
        else { num = String(format: "%.1f", value) }
        return unit.isEmpty ? num : "\(num) \(unit)"
    }
}

/// A discovered Bluetooth OBD adapter the user can connect to.
struct OBDDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    static func == (a: OBDDevice, b: OBDDevice) -> Bool { a.id == b.id }
}

/// Connects to a Bluetooth LE ELM327-style OBD-II adapter, runs the ELM327
/// init handshake, then polls a set of PIDs in a strict request/response queue
/// (one command out, wait for the ">" prompt, then the next). Unsupported PIDs
/// (those the Bolt answers with "NO DATA"/errors) are detected and dropped so
/// only live, meaningful values are shown.
///
/// BLE ELM327 clones vary wildly in their advertised service/characteristic
/// UUIDs, so we scan broadly and pick the write/notify characteristics by their
/// properties rather than hard-coded UUIDs.
@MainActor
final class OBDManager: NSObject, ObservableObject {
    static let shared = OBDManager()

    enum Phase: Equatable {
        case idle
        case bluetoothOff
        case scanning
        case connecting(String)
        case initializing
        case live
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Not connected"
            case .bluetoothOff: return "Turn on Bluetooth"
            case .scanning: return "Searching for adapter…"
            case .connecting(let n): return "Connecting to \(n)…"
            case .initializing: return "Initializing…"
            case .live: return "Live"
            case .failed(let m): return m
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var discovered: [OBDDevice] = []
    @Published private(set) var readings: [String: OBDReading] = [:]

    var isConnected: Bool {
        if case .live = phase { return true }
        if case .initializing = phase { return true }
        return false
    }

    /// Readings suitable for a dashboard, in poll order (voltage first).
    var latestReadable: [OBDReading] {
        var out: [OBDReading] = []
        if let v = readings["ATRV"] { out.append(v) }
        out += Self.pollPlan.compactMap { readings[$0.request] }
        return out
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    /// Strong references to peripherals seen this scan, so connect() is reliable.
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    /// Service UUIDs commonly advertised by ELM327 BLE clones — used to surface
    /// adapters that advertise without a readable name.
    private static let knownOBDServices: Set<CBUUID> = [
        CBUUID(string: "FFF0"), CBUUID(string: "FFE0"),
        CBUUID(string: "FFE1"), CBUUID(string: "18F0")
    ]
    /// Characteristic UUIDs known to carry ELM327 traffic on common clones.
    private static let knownChars: Set<CBUUID> = [
        CBUUID(string: "FFE1"), CBUUID(string: "FFF1"), CBUUID(string: "FFF2"),
        CBUUID(string: "2AF0"), CBUUID(string: "2AF1")
    ]

    private var initStarted = false
    private var receivedBytes = false
    private var watchdog: Timer?
    /// The CAN header currently set on the adapter (to avoid redundant ATSH).
    private var lastHeader: String?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var writeType: CBCharacteristicWriteType = .withResponse

    private var buffer = ""
    private var pollTimer: Timer?

    /// The command currently awaiting a ">" prompt, and what to do with its reply.
    private var pending: (command: String, handler: (String) -> Void)?
    private var commandQueue: [(String, (String) -> Void)] = []

    // MARK: - PID plan

    struct PID {
        /// Full request hex: mode-01 like "010D", or mode-22 like "2243AF".
        let request: String
        /// CAN header to address (e.g. "7E4" for the Bolt BECM). nil = broadcast.
        let header: String?
        let label: String
        let unit: String
        let icon: String
        /// Decode the data bytes (after the echoed mode + PID) into a value.
        let decode: ([Int]) -> Double?
    }

    /// Poll plan. The Bolt's real EV battery data lives in GM manufacturer
    /// (mode-22) PIDs addressed to the BECM at header 7E4 — the same ones
    /// Torque Pro / Car Scanner use (sourced from the community allev.info list).
    /// A few standard (mode-01) PIDs follow for when the car is awake/driving.
    static let pollPlan: [PID] = [
        // ---- GM Bolt EV extended (header 7E4, mode 22) ----
        PID(request: "2243AF", header: "7E4", label: "State of Charge", unit: "%", icon: "battery.100") { b in
            b.count >= 2 ? (Double(b[0]) * 256 + Double(b[1])) * 100 / 65535 : nil
        },
        PID(request: "2245F9", header: "7E4", label: "Usable Capacity", unit: "kWh", icon: "bolt.square.fill") { b in
            b.count >= 2 ? (Double(b[0]) * 256 + Double(b[1])) * 0.0032 : nil
        },
        PID(request: "2240D4", header: "7E4", label: "Battery Current", unit: "A", icon: "bolt.fill") { b in
            guard b.count >= 2 else { return nil }
            let a = b[0] > 127 ? b[0] - 256 : b[0]            // signed high byte
            return (Double(a) * 256 + Double(b[1])) / 20
        },
        PID(request: "22433C", header: "7E4", label: "Max Cell", unit: "V", icon: "arrow.up.to.line.compact") { b in
            guard b.count >= 2 else { return nil }
            let v = (Double(b[0]) * 256 + Double(b[1])) * 0.52   // millivolts
            return v > 100 ? v / 1000 : v
        },
        PID(request: "22433B", header: "7E4", label: "Min Cell", unit: "V", icon: "arrow.down.to.line.compact") { b in
            guard b.count >= 2 else { return nil }
            let v = (Double(b[0]) * 256 + Double(b[1])) * 0.52
            return v > 100 ? v / 1000 : v
        },
        PID(request: "22434F", header: "7E4", label: "Battery Temp", unit: "°F", icon: "thermometer.medium") { b in
            b.first.map { (Double($0) - 40) * 9/5 + 32 }
        },
        PID(request: "2241A4", header: "7E4", label: "Coolant Temp", unit: "°F", icon: "thermometer.snowflake") { b in
            b.first.map { (Double($0) - 40) * 9/5 + 32 }
        },
        // ---- Standard OBD-II (broadcast, mode 01) ----
        PID(request: "010D", header: nil, label: "Speed", unit: "mph", icon: "speedometer") { b in
            b.first.map { Double($0) * 0.621371 }
        },
        PID(request: "0142", header: nil, label: "Module Voltage", unit: "V", icon: "minus.plus.batteryblock.fill") { b in
            b.count >= 2 ? (Double(b[0]) * 256 + Double(b[1])) / 1000 : nil
        }
    ]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Lifecycle

    func startScan() {
        guard central.state == .poweredOn else {
            phase = .bluetoothOff
            return
        }
        discovered = []
        discoveredPeripherals = [:]
        phase = .scanning
        // nil services: many ELM327 clones don't advertise a usable service UUID.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func connect(_ device: OBDDevice) {
        let p = discoveredPeripherals[device.id]
            ?? central.retrievePeripherals(withIdentifiers: [device.id]).first
        guard let p else { return }
        central.stopScan()
        // Reset per-connection state.
        initStarted = false
        receivedBytes = false
        writeChar = nil
        notifyChar = nil
        commandQueue = []
        pending = nil
        buffer = ""
        lastHeader = nil
        peripheral = p
        p.delegate = self
        phase = .connecting(device.name)
        central.connect(p)
    }

    func disconnect() {
        pollTimer?.invalidate(); pollTimer = nil
        watchdog?.invalidate(); watchdog = nil
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        readings = [:]
        commandQueue = []
        pending = nil
        buffer = ""
        initStarted = false
        receivedBytes = false
        writeChar = nil
        notifyChar = nil
        lastHeader = nil
        phase = .idle
    }

    // MARK: - ELM327 command queue

    private func enqueue(_ command: String, handler: @escaping (String) -> Void) {
        commandQueue.append((command, handler))
        pumpQueue()
    }

    private func pumpQueue() {
        guard pending == nil, !commandQueue.isEmpty,
              let peripheral, let writeChar else { return }
        let (command, handler) = commandQueue.removeFirst()
        pending = (command, handler)
        buffer = ""
        let line = command + "\r"
        peripheral.writeValue(Data(line.utf8), for: writeChar, type: writeType)
    }

    /// Called when a complete ELM327 reply (terminated by ">") arrives.
    private func completePending() {
        guard let (_, handler) = pending else { return }
        let reply = buffer
        pending = nil
        handler(reply)
        pumpQueue()
    }

    private func runInitThenPoll() {
        phase = .initializing
        // ATZ reset, echo/linefeed/spaces off, headers off, auto protocol.
        for cmd in ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"] {
            enqueue(cmd) { _ in }
        }
        // A throwaway 0100 to make the adapter negotiate the protocol.
        enqueue("0100") { [weak self] _ in
            Task { @MainActor in self?.beginPolling() }
        }
    }

    private func beginPolling() {
        watchdog?.invalidate(); watchdog = nil
        phase = .live
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
        pollOnce()
    }

    private func pollOnce() {
        // ATRV reads the adapter's measured port voltage and works even with the
        // ECUs asleep — a guaranteed reading that proves the link is alive.
        enqueue("ATRV") { [weak self] reply in
            Task { @MainActor in self?.handleVoltage(reply) }
        }
        // Poll every PID each cycle (no permanent drop) so values appear the
        // moment the car wakes; we simply display whichever ones answer.
        for pid in Self.pollPlan {
            // Switch the CAN header when needed (mode-22 PIDs target the BECM).
            let header = pid.header ?? "7DF"
            if header != lastHeader {
                lastHeader = header
                enqueue("ATSH" + header) { _ in }
            }
            enqueue(pid.request) { [weak self] reply in
                Task { @MainActor in self?.handlePIDReply(pid, reply: reply) }
            }
        }
    }

    private func handleVoltage(_ reply: String) {
        // Reply looks like "12.5V". Extract the number.
        let digits = reply.filter { $0.isNumber || $0 == "." }
        guard let v = Double(digits), v > 1, v < 20 else { return }
        readings["ATRV"] = OBDReading(command: "ATRV", label: "Battery (12V)",
                                      value: v, unit: "V",
                                      systemImage: "minus.plus.batteryblock.fill")
    }

    private func handlePIDReply(_ pid: PID, reply: String) {
        let cleaned = reply.uppercased()
        // Unanswered/unsupported this cycle — leave any prior reading as-is and
        // try again next cycle (the car may simply be asleep right now).
        if cleaned.contains("NO DATA") || cleaned.contains("UNABLE")
            || cleaned.contains("ERROR") || cleaned.contains("STOPPED")
            || cleaned.contains("SEARCHING") || cleaned.contains("?") {
            return
        }
        guard let bytes = Self.dataBytes(from: reply, request: pid.request),
              let value = pid.decode(bytes) else { return }
        readings[pid.request] = OBDReading(command: pid.request, label: pid.label,
                                           value: value, unit: pid.unit, systemImage: pid.icon)
    }

    /// Extract the data bytes from an ELM327 reply for a given request, handling
    /// both mode-01 ("010D" → "41 0D …") and mode-22 ("2243AF" → "62 43 AF …").
    static func dataBytes(from reply: String, request: String) -> [Int]? {
        // Request bytes: "2243AF" → ["22","43","AF"].
        let reqBytes = stride(from: 0, to: request.count, by: 2).compactMap { off -> String? in
            let s = request.index(request.startIndex, offsetBy: off)
            guard let e = request.index(s, offsetBy: 2, limitedBy: request.endIndex) else { return nil }
            return String(request[s..<e]).uppercased()
        }
        guard let modeHex = reqBytes.first, let mode = Int(modeHex, radix: 16) else { return nil }
        let respMode = String(format: "%02X", mode | 0x40)   // 01→41, 22→62
        let pidBytes = Array(reqBytes.dropFirst())            // ["43","AF"] or ["0D"]

        // Flatten the whole reply into a stream of 2-char hex byte tokens.
        var flat: [String] = []
        let tokens = reply
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">", with: " ")
            .split(separator: " ")
            .map { String($0).uppercased() }
        for t in tokens where t.count % 2 == 0 && t.allSatisfy({ $0.isHexDigit }) {
            flat.append(contentsOf: stride(from: 0, to: t.count, by: 2).map {
                let s = t.index(t.startIndex, offsetBy: $0)
                let e = t.index(s, offsetBy: 2)
                return String(t[s..<e])
            })
        }

        // Find [respMode, pidBytes…] and return everything after it.
        let needle = [respMode] + pidBytes
        guard needle.count <= flat.count else { return nil }
        for i in 0...(flat.count - needle.count) where Array(flat[i..<i+needle.count]) == needle {
            return flat[(i + needle.count)...].compactMap { Int($0, radix: 16) }
        }
        return nil
    }
}

extension OBDManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn: if case .bluetoothOff = phase { phase = .idle }
            case .poweredOff, .unauthorized, .unsupported: phase = .bluetoothOff
            default: break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let advServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let advertisesOBD = advServices.contains { Self.knownOBDServices.contains($0) }
        // Keep anything with a name, or unnamed devices that advertise an OBD
        // service UUID (cheap clones often advertise no name until connected).
        guard let rawName = advName.flatMap({ $0.isEmpty ? nil : $0 }) ?? (advertisesOBD ? "OBD Adapter" : nil)
        else { return }
        let id = peripheral.identifier
        Task { @MainActor in
            discoveredPeripherals[id] = peripheral
            let device = OBDDevice(id: id, name: rawName)
            let up = rawName.uppercased()
            let looksOBD = advertisesOBD || ["OBD", "ELM", "VGATE", "VLINK", "VEEPEAK", "OBDLINK"]
                .contains { up.contains($0) }
            if let idx = discovered.firstIndex(of: device) {
                discovered[idx] = device   // refresh
            } else if looksOBD {
                discovered.insert(device, at: 0)
            } else {
                discovered.append(device)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            phase = .initializing
            armWatchdog()
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in phase = .failed("Couldn't connect to the adapter.") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            pollTimer?.invalidate(); pollTimer = nil
            if case .failed = phase {} else { phase = .idle }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                let props = char.properties
                let known = Self.knownChars.contains(char.uuid)

                // Notify endpoint: take a known char outright, else the first one.
                if props.contains(.notify) || props.contains(.indicate) {
                    if notifyChar == nil || known {
                        notifyChar = char
                        peripheral.setNotifyValue(true, for: char)
                    }
                }
                // Write endpoint: prefer writeWithoutResponse / known chars.
                if props.contains(.writeWithoutResponse) || props.contains(.write) {
                    let preferNoResponse = props.contains(.writeWithoutResponse)
                    if writeChar == nil || known {
                        writeChar = char
                        writeType = preferNoResponse ? .withoutResponse : .withResponse
                    }
                }
            }
            armWatchdog()
            // Fallback: if the notify-enabled callback never fires, start anyway.
            if writeChar != nil, notifyChar != nil, !initStarted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    Task { @MainActor in self?.startInitIfReady() }
                }
            }
        }
    }

    /// Called when notifications are actually enabled — only now is it safe to
    /// send commands and expect replies.
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if characteristic.isNotifying { startInitIfReady() }
        }
    }

    private func startInitIfReady() {
        guard !initStarted, writeChar != nil, notifyChar != nil else { return }
        initStarted = true
        runInitThenPoll()
    }

    /// If we can't reach a live state in time, stop spinning and explain.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if case .live = self.phase { return }
                let gotBytes = self.receivedBytes
                self.disconnect()
                self.phase = .failed(gotBytes
                    ? "Adapter connected but isn't answering OBD-II. Turn the car to ON/Ready and try again."
                    : "Connected, but no data from the adapter. It may be a non-OBD device or need its PIN — try another adapter.")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .ascii) else { return }
        Task { @MainActor in
            receivedBytes = true
            buffer += text
            if buffer.contains(">") { completePending() }
        }
    }
}
