# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Installation

Add the package via Swift Package Manager:

```
https://github.com/pawankmrai/swift-utils.git
```

Each utility is an independent library — import only what you need:

| Library | Import | What's inside |
|---------|--------|---------------|
| `SwiftUtilsExtensions` | `import SwiftUtilsExtensions` | String, Array, Date extensions |
| `SwiftUtilsNetworking` | `import SwiftUtilsNetworking` | APIClient, request/response helpers |
| `SwiftUtilsStorage` | `import SwiftUtilsStorage` | UserDefaults property wrapper, Keychain |
| `SwiftUtilsConcurrency` | `import SwiftUtilsConcurrency` | Debouncer, Throttler, async helpers |
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
        .product(name: "SwiftUtilsConcurrency", package: "swift-utils"),
    ]
)
```

## Utilities

### SwiftUtilsExtensions

**String+Extensions** — Common string helpers including email validation, trimming, numeric checks, truncation, slugification, and camelCase-to-snake_case conversion.

### SwiftUtilsNetworking

**APIClient** — A lightweight, async/await-based HTTP client built on URLSession. Supports GET, POST, and other methods with automatic JSON encoding/decoding, configurable headers, and snake_case key strategy out of the box.

### SwiftUtilsStorage

**UserDefaultsWrapper** — A `@propertyWrapper` for type-safe UserDefaults access. Supports default values, optional types, and custom suites. Drop it on a static property and read/write UserDefaults without string-key typos.

### SwiftUtilsConcurrency

**DebounceThrottle** — Thread-safe `Debouncer` and `Throttler` classes for rate-limiting closure execution. The debouncer waits for a quiet period before firing (ideal for search-as-you-type). The throttler caps execution frequency with `.leading`, `.trailing`, or `.leadingAndTrailing` modes (ideal for scroll handlers and analytics events).

## Structure

```
Sources/
├── Extensions/       # SwiftUtilsExtensions target
├── Networking/       # SwiftUtilsNetworking target
├── Storage/          # SwiftUtilsStorage target
└── Concurrency/      # SwiftUtilsConcurrency target
Tests/
├── ExtensionsTests/
├── NetworkingTests/
├── StorageTests/
└── ConcurrencyTests/
```

## License

MIT
