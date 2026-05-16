# KeychainWrapper

A type-safe wrapper around iOS Keychain Services for securely storing strings, Data, and Codable types.

## API

| Method | Description |
|---|---|
| `set(_:forKey:)` | Store a string value |
| `setData(_:forKey:)` | Store raw Data |
| `set(_:forKey:)` (Codable) | Store any Codable object |
| `string(forKey:)` | Retrieve a string |
| `data(forKey:)` | Retrieve raw Data |
| `object(forKey:)` (Codable) | Retrieve a decoded object |
| `delete(forKey:)` | Remove an item |
| `deleteAll()` | Remove all items for this service |

## Examples

```swift
import SwiftUtilsStorage

let keychain = KeychainWrapper()

// Store and retrieve strings
try keychain.set("s3cret_token", forKey: "auth_token")
let token: String? = try keychain.string(forKey: "auth_token")

// Store Codable objects
struct Credentials: Codable {
    let username: String
    let refreshToken: String
}

let creds = Credentials(username: "pawan", refreshToken: "abc123")
try keychain.set(creds, forKey: "user_credentials")
let saved: Credentials? = try keychain.object(forKey: "user_credentials")

// Delete a specific item
try keychain.delete(forKey: "auth_token")

// Custom accessibility level
let secureKeychain = KeychainWrapper(
    service: "com.myapp.secure",
    accessibility: .whenUnlocked
)

// Access group for sharing between apps
let sharedKeychain = KeychainWrapper(
    service: "com.myapp",
    accessGroup: "TEAMID.com.myapp.shared"
)
```
