import Foundation
import Security

// MARK: - KeychainError

/// Errors that can occur during Keychain operations.
public enum KeychainError: LocalizedError, Equatable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The requested item was not found in the Keychain."
        case .duplicateItem:
            return "An item with the same key already exists in the Keychain."
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status: \(status)."
        case .encodingFailed:
            return "Failed to encode the value for Keychain storage."
        case .decodingFailed:
            return "Failed to decode the value retrieved from the Keychain."
        }
    }
}

// MARK: - KeychainAccessibility

/// Controls when a Keychain item is accessible.
public enum KeychainAccessibility {
    /// Item is only accessible when the device is unlocked.
    case whenUnlocked
    /// Item is accessible after the first unlock until the device restarts.
    case afterFirstUnlock
    /// Item is always accessible (least secure, use sparingly).
    case always

    var cfValue: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .always:
            return kSecAttrAccessibleAlways
        }
    }
}

// MARK: - KeychainWrapper

/// A type-safe wrapper around the iOS Security framework's Keychain Services.
///
/// `KeychainWrapper` provides a simple, Swifty interface for storing, retrieving,
/// and deleting sensitive data in the device Keychain. It supports `String`, raw
/// `Data`, and any `Codable` type.
///
/// ```swift
/// let keychain = KeychainWrapper(service: "com.myapp")
///
/// // Store a token
/// try keychain.set("my-secret-token", forKey: "authToken")
///
/// // Retrieve it
/// let token: String? = try keychain.string(forKey: "authToken")
///
/// // Store a Codable object
/// try keychain.setCodable(credentials, forKey: "userCredentials")
/// let creds: UserCredentials? = try keychain.codable(forKey: "userCredentials")
///
/// // Remove an item
/// try keychain.remove(forKey: "authToken")
/// ```
public final class KeychainWrapper: @unchecked Sendable {

    // MARK: - Properties

    /// The service identifier used to namespace Keychain items.
    public let service: String

    /// The access group for sharing Keychain items across apps (optional).
    public let accessGroup: String?

    /// The default accessibility level for new items.
    public let accessibility: KeychainAccessibility

    // MARK: - Initialization

    /// Creates a new `KeychainWrapper`.
    ///
    /// - Parameters:
    ///   - service: A unique identifier for your app's Keychain items (e.g. bundle ID).
    ///   - accessGroup: Optional access group for sharing items between apps.
    ///   - accessibility: When the stored items should be accessible. Defaults to `.whenUnlocked`.
    public init(
        service: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    // MARK: - String Operations

    /// Stores a string value in the Keychain.
    ///
    /// - Parameters:
    ///   - value: The string to store.
    ///   - key: The key to associate with the value.
    /// - Throws: `KeychainError` if the operation fails.
    public func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try setData(data, forKey: key)
    }

    /// Retrieves a string value from the Keychain.
    ///
    /// - Parameter key: The key associated with the value.
    /// - Returns: The stored string, or `nil` if no item exists for the key.
    /// - Throws: `KeychainError` if the operation fails (other than item not found).
    public func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    // MARK: - Codable Operations

    /// Stores a `Codable` value in the Keychain as JSON.
    ///
    /// - Parameters:
    ///   - value: The `Codable` value to store.
    ///   - key: The key to associate with the value.
    /// - Throws: `KeychainError` if encoding or storage fails.
    public func setCodable<T: Codable>(_ value: T, forKey key: String) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw KeychainError.encodingFailed
        }
        try setData(data, forKey: key)
    }

    /// Retrieves and decodes a `Codable` value from the Keychain.
    ///
    /// - Parameters:
    ///   - key: The key associated with the value.
    ///   - type: The type to decode into (inferred automatically when possible).
    /// - Returns: The decoded value, or `nil` if no item exists for the key.
    /// - Throws: `KeychainError` if retrieval or decoding fails.
    public func codable<T: Codable>(forKey key: String, as type: T.Type = T.self) throws -> T? {
        guard let data = try data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw KeychainError.decodingFailed
        }
    }

    // MARK: - Data Operations

    /// Stores raw data in the Keychain. If an item with the same key exists, it is updated.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The key to associate with the data.
    /// - Throws: `KeychainError` if the operation fails.
    public func setData(_ data: Data, forKey key: String) throws {
        // Try to update first; if item doesn't exist, add it.
        let existingData = try self.data(forKey: key)

        if existingData != nil {
            let query = baseQuery(forKey: key)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: accessibility.cfValue,
            ]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        } else {
            var query = baseQuery(forKey: key)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = accessibility.cfValue

            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    /// Retrieves raw data from the Keychain.
    ///
    /// - Parameter key: The key associated with the data.
    /// - Returns: The stored data, or `nil` if no item exists for the key.
    /// - Throws: `KeychainError` if the operation fails (other than item not found).
    public func data(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.decodingFailed
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Removal

    /// Removes the item associated with the given key from the Keychain.
    ///
    /// - Parameter key: The key of the item to remove.
    /// - Throws: `KeychainError` if the operation fails (item not found is silently ignored).
    @discardableResult
    public func remove(forKey key: String) throws -> Bool {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes all items stored by this wrapper's service from the Keychain.
    ///
    /// - Throws: `KeychainError` if the operation fails.
    public func removeAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Existence Check

    /// Returns whether an item exists in the Keychain for the given key.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if an item exists, `false` otherwise.
    public func contains(_ key: String) throws -> Bool {
        return try data(forKey: key) != nil
    }

    // MARK: - Private Helpers

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
