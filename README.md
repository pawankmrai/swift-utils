# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Latest Addition

### Array+Extensions (Extensions)

A comprehensive set of Array and Sequence extensions for everyday iOS development. Includes safe subscripting, chunking, deduplication (by equality, hash, or key path), grouping, frequency counting, key-path-based sorting/min/max, and conditional appending.

```swift
import SwiftUtilsExtensions

// Safe subscript — no more "Index out of range" crashes
let items = ["a", "b", "c"]
items[safe: 1]   // Optional("b")
items[safe: 99]  // nil

// Chunk arrays for batch processing or grid layouts
[1, 2, 3, 4, 5].chunked(into: 2)  // [[1, 2], [3, 4], [5]]

// Remove duplicates while preserving order
[1, 3, 2, 3, 1, 4].uniquedFast()  // [1, 3, 2, 4]

// Deduplicate by a property
struct User { let id: Int; let name: String }
users.uniqued(by: \.id)

// Sort by key path
users.sorted(by: \.name)
users.sorted(by: \.name, ascending: false)

// Element frequencies
["a", "b", "a", "c", "a"].frequencies()  // ["a": 3, "b": 1, "c": 1]

// Conditional append
var tags = ["swift", "ios"]
tags.appendIfAbsent("swift")  // no-op, returns false
tags.appendIfAbsent("macOS")  // appends, returns true
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
| `SwiftUtilsExtensions` | `import SwiftUtilsExtensions` | String, Date, Array extensions |
| `SwiftUtilsNetworking` | `import SwiftUtilsNetworking` | APIClient, request/response helpers |
| `SwiftUtilsStorage` | `import SwiftUtilsStorage` | UserDefaults property wrapper, Keychain wrapper |
| `SwiftUtilsConcurrency` | `import SwiftUtilsConcurrency` | Debouncer, Throttler, async helpers |
| `SwiftUtilsHelpers` | `import SwiftUtilsHelpers` | Logger, Validator, DeepLinkHandler |
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

**Array+Extensions** — Safe subscripting (`[safe:]`), chunking, deduplication (preserving order via `uniqued()`, `uniquedFast()`, or `uniqued(by:)` for key paths), grouping by key path, frequency counting, key-path-based `min`/`max`/`sorted`, `compactMap(unwrapping:)` for optional key paths, and `appendIfAbsent(_:)`.

### Networking

**APIClient** — A lightweight, async/await-based HTTP client built on URLSession. Supports GET, POST, and other methods with automatic JSON encoding/decoding, configurable headers, and snake_case key strategy out of the box.

### Storage

**UserDefaultsWrapper** — A `@propertyWrapper` for type-safe UserDefaults access. Supports default values, optional types, and custom suites. Drop it on a static property and read/write UserDefaults without string-key typos.

**KeychainWrapper** — A type-safe wrapper around the iOS Keychain Services API. Securely store, retrieve, and delete strings, raw `Data`, or any `Codable` type. Supports configurable accessibility levels (`whenUnlocked`, `afterFirstUnlock`) and optional access groups for sharing items across apps.

### Concurrency

**DebounceThrottle** — Thread-safe `Debouncer` and `Throttler` classes for rate-limiting closure execution. The debouncer waits for a quiet period before firing (ideal for search-as-you-type). The throttler caps execution frequency with `.leading`, `.trailing`, or `.leadingAndTrailing` modes.

### Helpers

**SwiftLogger** — A configurable, thread-safe logger with severity levels (verbose through fatal), category tagging, and pluggable destinations. Ships with a `ConsoleDestination` that uses `os.Logger` in release builds and `print` in debug. Messages below the configured minimum level are discarded, and `@autoclosure` ensures expensive string interpolations are never evaluated when filtered out.

**Validator** — A composable, type-safe input validation framework. Build validators by chaining rules like `.nonEmpty()`, `.email()`, `.minLength(_:)`, `.strongPassword()`, `.pattern(_:)`, or custom predicates. Validate a value against all rules at once with `errors(for:)`, or short-circuit on the first failure with `firstError(for:)`. Includes built-in rules for strings, `Comparable` types (min/max/range), and optionals (`required`).

**DeepLinkHandler** — A declarative deep link routing system. Register URL patterns with named parameters (`:id`) and wildcards (`*`), then route incoming URLs to handlers with full context including extracted path parameters, query parameters, and scheme. Supports scheme filtering, fallback handlers, and dry-run matching via `canHandle(_:)`. Case-insensitive literal matching and first-match-wins priority.

## Structure

```
swift-utils/
├── Package.swift
├── README.md
├── Sources/
│   ├── Concurrency/
│   │   └── DebounceThrottle.swift
│   ├── Extensions/
│   │   ├── Array+Extensions.swift
│   │   ├── Date+Extensions.swift
│   │   └── String+Extensions.swift
│   ├── Helpers/
│   │   ├── DeepLinkHandler.swift
│   │   ├── Logger.swift
│   │   └── Validator.swift
│   ├── Networking/
│   │   └── APIClient.swift
│   └── Storage/
│       ├── KeychainWrapper.swift
│       └── UserDefaultsWrapper.swift
└── Tests/
    ├── ConcurrencyTests/
    │   └── DebounceThrottleTests.swift
    ├── ExtensionsTests/
    │   ├── ArrayExtensionsTests.swift
    │   ├── DateExtensionsTests.swift
    │   └── StringExtensionsTests.swift
    ├── HelpersTests/
    │   ├── DeepLinkHandlerTests.swift
    │   ├── LoggerTests.swift
    │   └── ValidatorTests.swift
    ├── NetworkingTests/
    │   └── APIClientTests.swift
    └── StorageTests/
        ├── KeychainWrapperTests.swift
        └── UserDefaultsWrapperTests.swift
```

## License

MIT
