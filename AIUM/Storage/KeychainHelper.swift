import Foundation
import Security

/// A simple wrapper for storing and retrieving string values in the Keychain.
enum KeychainHelper {
    @discardableResult
    static func save(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Codable convenience

    static func saveCodable<T: Codable>(_ value: T, service: String, account: String) throws {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        guard save(string, service: service, account: account) else {
            throw KeychainError.saveFailed
        }
    }

    static func loadCodable<T: Codable>(_ type: T.Type, service: String, account: String) throws -> T? {
        guard let string = load(service: service, account: account) else { return nil }
        guard let data = string.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum KeychainError: Error {
    case encodingFailed
    case saveFailed
}
