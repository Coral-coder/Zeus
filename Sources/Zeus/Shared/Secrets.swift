import Foundation

/// Reads non-account API keys from a gitignored `Secrets.plist` bundled at
/// build time. Account credentials/tokens live in the Keychain, never here.
///
/// Create `Sources/Zeus/Resources/Secrets.plist` (it's gitignored) with:
///   OpenChargeMapKey : <your key>
enum Secrets {
    private static let values: [String: Any] = {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }()

    static var openChargeMapKey: String {
        (values["OpenChargeMapKey"] as? String) ?? ""
    }
}
