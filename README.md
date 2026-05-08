# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Latest Addition

### KeychainWrapper (Storage)

A type-safe wrapper around the iOS Keychain Services API for securely storing sensitive data like tokens, passwords, and credentials.

```swift
import SwiftUtilsStorage

let keychain = KeychainWrapper(service: "com.myapp")

// Store and retrieve strings
try keychain.set("my-secret-token", forKey: "authToken")
let token = try keychain.string(forKey: "authToken") // "my-secret-token"

// Store Codable objects as JSON
struct Credentials: Codable {
    let username: String
    let apiKey: String
}

let creds = Credentials(username: "pawan", apiKey: "sk-12345")
try keychain.setCodable(creds, forKey: "credentials")
let restored: Credentials? = try keychain.codable(forKey: "credentials")

// Check existence and clean up
try keychain.contains("authToken")  // true
try keychain.remove(forKey: "authToken")
try keychain.removeAll()
```

---

## Installation

Add the package via Swift Package Manager:

```
https://github.com/pawankmrai/swift-utils.git
```

Each utility is an independent library — import only what you need:

| Library | Import | What's inside |
|---------|--------|---------------|
| `SwiftUtilsExtensions` | `import SwiftUtilsExtensions` | String, Date extensions |
| `SwiftUtilsNetworking` | `import SwiftUtilsNetworking` | APIClient, request/response helpers |
| `SwiftUtilsStorage` | `import SwiftUtilsStorage` | UserDefaults property wrapper, Keychain wrapper |
| `SwiftUtilsConcurrency` | `import SwiftUtilsConcurrency` | Debouncer, Throttler, async helpers |
| `SwiftUtilsHelpers` | `import SwiftUtilsHelpers` | Logger with pluggable destinations |
| `SwiftUtils` | `import SwiftUtils` | Everything (umbrella) |

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pawankmrai/swift-utils.git", branch: "main")
]

// Add only the targets you need:
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SwiftUtilsNetworking", package: "swift-utils"),
        .product(name: "SwiftUtilsStorage", package: "swift-utils"),
    ]
)
```

## Utilities

### Extensions

**String+Extensions** — Common string helpers including email validation, trimming, numeric checks, truncation, slugification, and camelCase-to-snake_case conversion.

**Date+Extensions** — Comprehensive date utilities with relative formatting, component access, date arithmetic, ISO 8601 parsing, and day-level comparisons (isToday, isYesterday, etc.).

### Networking

**APIClient** — A lightweight, async/await-based HTTP client built on URLSession. Supports GET, POST, and other methods with automatic JSON encoding/decoding, configurable headers, and snake_case key strategy out of the box.

### Storage

**UserDefaultsWrapper** — A `@propertyWrapper` for type-safe UserDefaults access. Supports default values, optional types, and custom suites. Drop it on a static property and read/write UserDefaults without string-key typos.

**KeychainWrapper** — A type-safe wrapper around the iOS Keychain Services API. Securely store, retrieve, and delete strings, raw `Data`, or any `Codable` type. Supports configurable accessibility levels (`whenUnlocked`, `afterFirstUnlock`) and optional access groups for sharing items across apps.

### Concurrency

**DebounceThrottle** — Thread-safe `Debouncer` and `Throttler` classes for rate-limiting closure execution. The debouncer waits for a quiet period before firing (ideal for search-as-you-type). The throttler caps execution frequency with `.leading`, `.trailing`, or `.leadingAndTrailing` modes.

### Helpers

**SwiftLogger** — A configurable, thread-safe logger with severity levels (verbose through fatal), category tagging, and pluggable destinations. Ships with a `ConsoleDestination` that uses `os.Logger` in release builds and `print` in debug. Messages below the configured minimum level are discarded, and `@autoclosure` ensures expensive string interpolations are never evaluated when filtered out.

## Structure

```
Sources/
├── Extensions/       # SwiftUtilsExtensions
├── Networking/       # SwiftUtilsNetworking
├── Storage/          # SwiftUtilsStorage
├── Concurrency/      # SwiftUtilsConcurrency
└── Helpers/          # SwiftUtilsHelpers
Tests/
├── ExtensionsTests/
├── NetworkingTests/
├── StorageTests/
├── ConcurrencyTests/
└── HelpersTests/
```

## License

MIT
