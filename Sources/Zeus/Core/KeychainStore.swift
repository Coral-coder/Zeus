import Foundation
import Security

/// Tiny Keychain wrapper for the few secrets Zeus holds: the GM token, the
/// OnStar config, and the command PIN. Items use `kSecAttrAccessGroup` so the
/// widget extension can read the token too (set `accessGroup` to your team's
/// shared keychain group).
enum KeychainStore {
    private static let service = "com.zeus.bolt"
    private static let accessGroup: String? = nil

    enum Key: String {
        case gmToken = "gm.token"
        case onStarConfig = "onstar.config"
        case commandPIN = "command.pin"
    }

    static func save<T: Encodable>(_ value: T, for key: Key) throws {
        let data = try JSONEncoder().encode(value)
        try saveData(data, for: key)
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = loadData(for: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(_ key: Key) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private static func saveData(_ data: Data, for key: Key) throws {
        var query = baseQuery(key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func loadData(for key: Key) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func baseQuery(_ key: Key) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }
}
