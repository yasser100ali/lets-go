import Foundation
import Security
import OSLog

/// A few generic-password items for this app.
nonisolated enum Keychain {
    private static let service = "com.yasser100ali.letsgo"
    private static let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "keychain")

    static func read(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound { log.error("Keychain read \(key, privacy: .public): \(status)") }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for key: String) {
        delete(key)
        var query = base(key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { log.error("Keychain write \(key, privacy: .public): \(status)") }
    }

    static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }

    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}
