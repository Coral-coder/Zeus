import Foundation

/// A prepared install: an `.ipa` staged on disk plus the metadata needed to
/// serve a private, token-gated OTA link. Native port of `ipa_sideload`'s
/// `src/store.js` (minus re-signing — Zeus serves bytes as-is).
struct SideloadInstall: Codable, Identifiable, Equatable {
    let id: String
    let installToken: String
    let ipaName: String
    let bundleID: String
    let version: String
    let title: String
    let sizeBytes: Int
    let createdAt: Date
    let sourceLabel: String
}

/// Tracks prepared installs and their staged `.ipa` files. State lives in a JSON
/// index under Application Support so links survive a relaunch.
final class SideloadStore {
    private let dir: URL
    private let indexURL: URL
    private let queue = DispatchQueue(label: "com.lightwave.zeus.sideload.store")
    private var installs: [String: SideloadInstall] = [:]

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("Sideload", isDirectory: true)
        indexURL = dir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func ipaURL(for id: String) -> URL { dir.appendingPathComponent("\(id).ipa") }

    static func token() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Stage raw `.ipa` bytes and register a token-gated install record.
    func stage(ipaData: Data, name: String, meta: IPAReader.Metadata, sourceLabel: String) throws -> SideloadInstall {
        let id = Self.token()
        try ipaData.write(to: ipaURL(for: id), options: .atomic)
        let install = SideloadInstall(
            id: id,
            installToken: Self.token(),
            ipaName: name,
            bundleID: meta.bundleID,
            version: meta.version,
            title: meta.title,
            sizeBytes: ipaData.count,
            createdAt: Date(),
            sourceLabel: sourceLabel
        )
        queue.sync {
            installs[id] = install
            persist()
        }
        return install
    }

    func get(_ id: String) -> SideloadInstall? { queue.sync { installs[id] } }

    func list() -> [SideloadInstall] {
        queue.sync { installs.values.sorted { $0.createdAt > $1.createdAt } }
    }

    func remove(_ id: String) {
        queue.sync {
            installs.removeValue(forKey: id)
            try? FileManager.default.removeItem(at: ipaURL(for: id))
            persist()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.iso.decode([String: SideloadInstall].self, from: data) else { return }
        installs = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder.iso.encode(installs) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
