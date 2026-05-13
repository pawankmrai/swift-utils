# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Latest Addition

### DeepLinkHandler (Helpers)

A composable deep link routing system for iOS apps. Register URL patterns with named parameters and wildcards, then route incoming URLs to the appropriate handlers with full context (path params, query params, scheme).

```swift
import SwiftUtilsHelpers

let router = DeepLinkHandler()

// Register routes with named path parameters
router.register("product/:id") { context in
    let productId = context.pathParameters["id"]!
    let source = context.queryParameters["ref"] ?? "organic"
    // Navigate to product detail
}

router.register("user/:userId/posts/:postId") { context in
    let userId = context.pathParameters["userId"]!
    let postId = context.pathParameters["postId"]!
    // Navigate to specific post
}

// Wildcard support
router.register("feed/*/comments") { _ in
    // Matches feed/anything/comments
}

// Fallback for unmatched URLs
router.setFallback { context in
    // Handle unknown deep links
}

// Handle incoming URL (e.g., from UIApplicationDelegate or SceneDelegate)
let url = URL(string: "myapp://product/42?ref=push")!
router.handle(url) // → matched, id="42", ref="push"

// Check without executing
router.canHandle(url) // → true
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
