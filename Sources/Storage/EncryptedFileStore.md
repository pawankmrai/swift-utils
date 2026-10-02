# EncryptedFileStore

Persists `Codable` values to disk encrypted with **AES-GCM** (CryptoKit), using a 256-bit key that by default is generated once and kept in the Keychain.

`EncryptedFileStore` fills the gap between `KeychainWrapper` (great for small secrets, awkward for larger payloads) and `CodableStore` / `FileManagerHelper` (convenient, but plaintext on disk). Use it for cached user profiles, offline health or finance records, draft messages, or any model you'd rather not leave readable in the app container or a device backup.

- **Authenticated encryption** — AES-GCM detects tampering or a wrong key and throws `EncryptedFileStoreError.decryptionFailed` instead of decoding garbage.
- **Fresh nonce per write** — saving the same value twice yields different ciphertext.
- **Hashed file names** — keys are SHA-256 hashed, so file names are filesystem-safe and don't reveal what's stored.
- **Defense in depth** — on iOS, files are written atomically with `.completeFileProtection`.
- **Pluggable keys** — `KeychainKeyProvider` (device-only, not backed up) for production, `InMemoryKeyProvider` for tests and previews, or your own `EncryptionKeyProvider`.

## API

| Type / Method | Description |
|---|---|
| `EncryptedFileStore(directory: URL, keyProvider: EncryptionKeyProvider = KeychainKeyProvider())` | Creates a store rooted at `directory`, creating the directory if needed |
| `EncryptedFileStore(directoryName: String, keyProvider:)` | Convenience init that stores files under `Application Support/<directoryName>` |
| `directory: URL` | The directory holding the encrypted `.enc` files |
| `save(_:forKey:) throws` | JSON-encodes, encrypts, and atomically writes a value, replacing any existing one |
| `load(_:forKey:) throws -> T?` | Reads and decrypts a value; returns `nil` if nothing is stored for `key` |
| `contains(_:) -> Bool` | Whether an encrypted file exists for `key` |
| `remove(forKey:) throws` | Deletes the file for `key` (no-op if missing) |
| `removeAll() throws` | Deletes every `.enc` file in the store's directory, leaving other files untouched |
| `protocol EncryptionKeyProvider` | `func key() throws -> SymmetricKey` — must return the same key every call |
| `KeychainKeyProvider(service:account:)` | Generates a 256-bit key on first use and persists it with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| `InMemoryKeyProvider(key:)` | Holds a key in memory (random by default) — for tests and SwiftUI previews |
| `EncryptedFileStoreError.decryptionFailed` | File was tampered with or encrypted with a different key |
| `EncryptedFileStoreError.keychain(OSStatus)` | Keychain read/write failed |

## Examples

### Basic usage

```swift
struct UserProfile: Codable {
    let id: UUID
    let name: String
    let email: String
}

let store = try EncryptedFileStore(directoryName: "SecureData")

try store.save(profile, forKey: "currentUser")

if let cached = try store.load(UserProfile.self, forKey: "currentUser") {
    showProfile(cached)
}
```

### Offline cache for sensitive API data

```swift
final class StatementsRepository {
    private let api: APIClient
    private let store = try! EncryptedFileStore(directoryName: "Statements")

    init(api: APIClient) { self.api = api }

    func statements(for accountID: String) async throws -> [Statement] {
        do {
            let fresh: [Statement] = try await api.get("/accounts/\(accountID)/statements")
            try store.save(fresh, forKey: "statements.\(accountID)")
            return fresh
        } catch {
            // Fall back to the encrypted offline copy when the network fails.
            if let cached = try store.load([Statement].self, forKey: "statements.\(accountID)") {
                return cached
            }
            throw error
        }
    }
}
```

### Handling tampering or a lost key

```swift
do {
    let draft = try store.load(Draft.self, forKey: "draft")
    editor.restore(draft)
} catch EncryptedFileStoreError.decryptionFailed {
    // The Keychain key was reset (e.g. device restore) or the file was modified.
    try? store.remove(forKey: "draft")
    editor.startFresh()
}
```

### Clearing everything on sign-out

```swift
func signOut() throws {
    try secureStore.removeAll()
    try keychain.removeAll()
    session.reset()
}
```

### Using a custom Keychain service / multiple stores

```swift
// Separate keys per signed-in user, so one user's data can't be read with another's key.
func store(for userID: String) throws -> EncryptedFileStore {
    try EncryptedFileStore(
        directoryName: "Users/\(userID)",
        keyProvider: KeychainKeyProvider(service: "com.example.app", account: "store.\(userID)")
    )
}
```

### Unit tests and SwiftUI previews

```swift
final class DraftServiceTests: XCTestCase {
    func testDraftIsPersisted() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try EncryptedFileStore(directory: dir, keyProvider: InMemoryKeyProvider())

        let service = DraftService(store: store)
        try service.saveDraft("Hello")

        XCTAssertEqual(try store.load(String.self, forKey: "draft"), "Hello")
    }
}
```

### Bringing your own key (e.g. derived from a passcode)

```swift
struct PasscodeKeyProvider: EncryptionKeyProvider {
    let passcode: String
    let salt: Data

    func key() throws -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(passcode.utf8)),
            salt: salt,
            outputByteCount: 32
        )
    }
}

let vault = try EncryptedFileStore(
    directoryName: "Vault",
    keyProvider: PasscodeKeyProvider(passcode: enteredPasscode, salt: storedSalt)
)
```
