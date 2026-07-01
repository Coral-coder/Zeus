import Foundation
import ZIPFoundation
import CZsign

/// Re-signs an `.ipa` in-process with zsign (the vendored C++ signer). Native
/// equivalent of `ipa_sideload`'s zsign step — but running on the device.
///
/// Given a signing identity (certificate + private key + provisioning profile),
/// it extracts the `.ipa`, hands the `.app` payload folder to zsign, and repacks
/// a freshly-signed `.ipa`.
enum Signer {
    struct Identity {
        let certPath: URL        // PEM/DER cert, or empty if key is a .p12
        let keyPath: URL         // PEM/DER private key, or a .p12
        let provisionPath: URL   // .mobileprovision to embed
        var password: String = "" // for encrypted key / .p12
        var newBundleID: String? = nil
    }

    enum SignError: LocalizedError {
        case extractFailed(String)
        case zsignFailed(String)
        case repackFailed(String)
        var errorDescription: String? {
            switch self {
            case .extractFailed(let m): return "Couldn't unpack the .ipa: \(m)"
            case .zsignFailed(let m): return "Re-signing failed: \(m)"
            case .repackFailed(let m): return "Couldn't repack the signed .ipa: \(m)"
            }
        }
    }

    /// Re-sign raw `.ipa` bytes and return the re-signed `.ipa` bytes.
    static func resign(ipaData: Data, with identity: Identity) throws -> Data {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("resign-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // 1. Extract the .ipa (a zip) → root/ containing Payload/<App>.app
        let root = work.appendingPathComponent("root", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let ipaFile = work.appendingPathComponent("in.ipa")
            try ipaData.write(to: ipaFile)
            try fm.unzipItem(at: ipaFile, to: root)
        } catch {
            throw SignError.extractFailed(error.localizedDescription)
        }

        // 2. Re-sign the payload folder in place with zsign.
        var err: NSString?
        let ok = ZsignBridge.signAppFolder(
            root.path,
            certPath: identity.certPath.path,
            keyPath: identity.keyPath.path,
            password: identity.password,
            provisionPath: identity.provisionPath.path,
            bundleId: identity.newBundleID,
            error: &err
        )
        guard ok else { throw SignError.zsignFailed((err as String?) ?? "unknown zsign error") }

        // 3. Repack Payload/ back into a new .ipa.
        let payload = root.appendingPathComponent("Payload", isDirectory: true)
        let out = work.appendingPathComponent("out.ipa")
        do {
            try fm.zipItem(at: payload, to: out, shouldKeepParent: true, compressionMethod: .deflate)
            return try Data(contentsOf: out)
        } catch {
            throw SignError.repackFailed(error.localizedDescription)
        }
    }
}
