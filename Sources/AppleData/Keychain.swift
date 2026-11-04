#if canImport(Security)
    import Foundation
    import Security

    /// Stores the optional Claude API key in the Keychain, never in UserDefaults or the bundle.
    public enum Keychain {
        static let service = "com.kith.app"

        public static func read(_ account: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        @discardableResult
        public static func write(_ value: String, for account: String) -> Bool {
            delete(account)
            guard !value.isEmpty else { return true }
            let attributes: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: Data(value.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }

        public static func delete(_ account: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
#endif
