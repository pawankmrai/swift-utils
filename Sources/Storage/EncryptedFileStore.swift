import Foundation
import CryptoKit
import Security

/// Supplies the symmetric key used by ``EncryptedFileStore``.
///
/// Implementations must return the *same* key on every call, otherwise
/// previously written files can no longer be decrypted.
public protocol EncryptionKeyProvider: Sendable {
    /// Returns the 256-bit key used for AES-GCM encryption.
    func key() throws -> SymmetricKey
}

/// Errors thrown by ``EncryptedFileStore`` and its key providers.
public enum EncryptedFileStoreError: Error, Equatable {
    /// The Keychain returned an unexpected `OSStatus`.
    case keychain(OSStatus)
    /// The file exists but could not be authenticated/decrypted
    /// (wrong key or tampered contents).
    case decryptionFailed
}

/// Key provider that holds a key in memory. Ideal for tests and previews.
public struct InMemoryKeyProvider: EncryptionKeyProvider {
    private let storedKey: SymmetricKey

    /// Creates a provider with the given key, or a fresh random 256-bit key.
    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.storedKey = key
    }

    public func key() throws -> SymmetricKey { storedKey }
}

/// Key provider that generates a 256-bit key on first use and persists it in
/// the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so the
/// key never leaves the device and is excluded from backups.
public struct KeychainKeyProvider: EncryptionKeyProvider {
    /// Keychain service name.
    public let service: String
    /// Keychain account name identifying this key.
    public let account: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "SwiftUtils",
                account: String = "EncryptedFileStore.key") {
        self.service = service
        self.account = account
    }

    public func key() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw EncryptedFileStoreError.keychain(status) }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw EncryptedFileStoreError.keychain(addStatus) }
        return newKey
    }
}

/// Persists `Codable` values to disk encrypted with AES-GCM (CryptoKit).
///
/// Each value is JSON-encoded, sealed with a 256-bit key from an
/// ``EncryptionKeyProvider``, and written atomically with
/// `.completeFileProtection`. AES-GCM is authenticated, so tampered or
/// foreign files fail loudly with ``EncryptedFileStoreError/decryptionFailed``
/// instead of decoding garbage.
///
/// ```swift
/// let store = try EncryptedFileStore(directoryName: "Secure")
/// try store.save(profile, forKey: "profile")
/// let loaded: UserProfile? = try store.load(UserProfile.self, forKey: "profile")
/// ```
public final class EncryptedFileStore: @unchecked Sendable {
    /// Directory where encrypted files are stored.
    public let directory: URL
    private let keyProvider: EncryptionKeyProvider
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    /// Creates a store rooted at `directory`, creating it if needed.
    public init(directory: URL, keyProvider: EncryptionKeyProvider = KeychainKeyProvider()) throws {
        self.directory = directory
        self.keyProvider = keyProvider
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Convenience initializer that stores files in
    /// `Application Support/<directoryName>`.
    public convenience init(directoryName: String,
                            keyProvider: EncryptionKeyProvider = KeychainKeyProvider()) throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        try self.init(directory: base.appendingPathComponent(directoryName, isDirectory: true),
                      keyProvider: keyProvider)
    }

    /// Encrypts and writes `value` for `key`, replacing any existing file.
    public func save<T: Encodable>(_ value: T, forKey key: String) throws {
        let plaintext = try encoder.encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: keyProvider.key())
        guard let combined = sealed.combined else { throw EncryptedFileStoreError.decryptionFailed }
        lock.lock(); defer { lock.unlock() }
        #if os(iOS)
        try combined.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
        #else
        try combined.write(to: fileURL(for: key), options: .atomic)
        #endif
    }

    /// Reads and decrypts the value for `key`, or returns `nil` if no file exists.
    public func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        lock.lock()
        let data = try? Data(contentsOf: fileURL(for: key))
        lock.unlock()
        guard let data else { return nil }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            plaintext = try AES.GCM.open(box, using: keyProvider.key())
        } catch let error as EncryptedFileStoreError {
            throw error
        } catch {
            throw EncryptedFileStoreError.decryptionFailed
        }
        return try decoder.decode(T.self, from: plaintext)
    }

    /// Whether an encrypted file exists for `key`.
    public func contains(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    /// Deletes the file for `key`. No-op if it doesn't exist.
    public func remove(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Deletes every file managed by this store.
    public func removeAll() throws {
        lock.lock(); defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "enc" {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// File URL for `key`. Keys are hashed (SHA-256) so arbitrary strings are
    /// filesystem-safe and file names don't leak what's stored.
    func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("enc")
    }
}
