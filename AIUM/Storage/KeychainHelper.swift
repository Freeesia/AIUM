import Foundation
import Security

/// A simple wrapper for storing and retrieving string values in the Keychain.
enum KeychainHelper {
    /// Authentication tokens need to remain available when iOS launches the app
    /// in the background while the device is locked. Keeping them device-only
    /// also avoids migrating a live session to another device through a backup.
    static let tokenAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    static func save(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        let updatedAttributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: tokenAccessibility,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            updatedAttributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(operation: "update", status: updateStatus)
        }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = tokenAccessibility
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(operation: "save", status: status)
        }
    }

    static func load(service: String, account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(operation: "load", status: status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return value
    }

    static func delete(service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(operation: "delete", status: status)
        }
    }

    // MARK: - Codable convenience

    static func saveCodable<T: Codable>(_ value: T, service: String, account: String) throws {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(string, service: service, account: account)
    }

    static func loadCodable<T: Codable>(_ type: T.Type, service: String, account: String) throws -> T? {
        guard let string = try load(service: service, account: account) else { return nil }
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case unexpectedStatus(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "Could not encode credentials for Keychain storage.")
        case .decodingFailed:
            return String(localized: "Could not decode credentials from Keychain storage.")
        case .unexpectedStatus(let operation, let status):
            let localizedOperation: String
            switch operation {
            case "update": localizedOperation = String(localized: "update")
            case "save": localizedOperation = String(localized: "save")
            case "load": localizedOperation = String(localized: "load")
            case "delete": localizedOperation = String(localized: "delete")
            default: localizedOperation = operation
            }
            let message = SecCopyErrorMessageString(status, nil) as String?
                ?? String(localized: "Unknown Keychain error")
            return String.localizedStringWithFormat(
                String(localized: "Keychain %@ failed (%lld): %@"),
                localizedOperation,
                Int64(status),
                message
            )
        }
    }
}
