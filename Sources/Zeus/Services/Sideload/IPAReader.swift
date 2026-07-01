import Foundation
import ZIPFoundation

/// Pulls an `.ipa` out of raw bytes (a `.ipa` directly, or a zip/artifact that
/// contains one) and reads the iOS app metadata needed for the OTA manifest.
/// Native port of `ipa_sideload`'s `src/ipa.js`.
enum IPAReader {
    struct Metadata {
        let bundleID: String
        let version: String
        let title: String
    }

    enum ReadError: LocalizedError {
        case notAnArchive
        case noIPA(String)
        case noInfoPlist

        var errorDescription: String? {
            switch self {
            case .notAnArchive: return "That file isn't a valid .ipa or zip archive."
            case .noIPA(let contents): return "No .ipa found inside the archive. Contents: \(contents)"
            case .noInfoPlist: return "Could not read Info.plist from the .ipa — it may be malformed."
            }
        }
    }

    private static let appRegex = "^Payload/[^/]+\\.app/"
    private static let infoRegex = "^Payload/[^/]+\\.app/Info\\.plist$"

    /// Accept any iOS payload — a raw `.ipa`, or a zip/artifact containing one —
    /// and return the actual `.ipa` bytes plus a sensible filename.
    static func resolveIPA(_ data: Data, name: String) throws -> (name: String, data: Data) {
        guard let archive = Archive(data: data, accessMode: .read) else { throw ReadError.notAnArchive }

        // Already an .ipa (has its own Payload/<App>.app tree) → use as-is.
        if archive.contains(where: { matches($0.path, appRegex) }) {
            let base = name.lowercased().hasSuffix(".ipa") ? name : "\(name).ipa"
            return ((base as NSString).lastPathComponent, data)
        }

        // Otherwise it's a wrapper (e.g. a GitHub artifact zip) — dig the .ipa out.
        guard let entry = archive.first(where: {
            !$0.path.hasSuffix("/") && $0.path.lowercased().hasSuffix(".ipa")
        }) else {
            var names: [String] = []
            for e in archive where names.count < 20 { names.append(e.path) }
            throw ReadError.noIPA(names.isEmpty ? "(empty)" : names.joined(separator: ", "))
        }
        var out = Data()
        _ = try archive.extract(entry) { out.append($0) }
        return ((entry.path as NSString).lastPathComponent, out)
    }

    /// Read `Payload/<App>.app/Info.plist` (binary OR xml) → manifest fields.
    static func metadata(ipaData: Data, fallbackName: String) throws -> Metadata {
        guard let archive = Archive(data: ipaData, accessMode: .read) else { throw ReadError.notAnArchive }
        guard let info = archive.first(where: { matches($0.path, infoRegex) }) else {
            throw ReadError.noInfoPlist
        }
        var raw = Data()
        _ = try archive.extract(info) { raw.append($0) }

        let plist = (try? PropertyListSerialization.propertyList(from: raw, options: [], format: nil)) as? [String: Any] ?? [:]
        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        guard !bundleID.isEmpty else { throw ReadError.noInfoPlist }
        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String) ?? "1.0"
        let title = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? (fallbackName as NSString).deletingPathExtension
        return Metadata(bundleID: bundleID, version: version, title: title)
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }
}
