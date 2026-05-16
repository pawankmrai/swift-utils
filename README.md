# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Latest Addition

### FeatureFlagManager (Helpers)

A lightweight, type-safe feature flag manager with layered value resolution, local overrides, and change observation. Define flags as static constants, read them anywhere, and override them for testing or debug menus. Plug in remote providers (Firebase, LaunchDarkly, etc.) via the `FeatureFlagProvider` protocol.

```swift
import SwiftUtilsHelpers

// Define flags
extension FeatureFlag {
    static let newOnboarding = FeatureFlag<Bool>(key: "new_onboarding", defaultValue: false)
    static let maxRetries = FeatureFlag<Int>(key: "max_retries", defaultValue: 3)
}

let manager = FeatureFlagManager.shared

// Read a flag
if manager.isEnabled(.newOnboarding) {
    showNewOnboarding()
}

// Set a local override (great for debug menus)
manager.setOverride(true, for: .newOnboarding)

// Observe changes
let token = manager.observe(.newOnboarding) { change in
    print("Changed: \(change.oldValue) → \(change.newValue)")
}

// Register a remote provider
let remoteFlags = DictionaryFlagProvider(values: ["max_retries": 5])
manager.registerProvider(remoteFlags)
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
| `SwiftUtilsHelpers` | `import SwiftUtilsHelpers` | Logger, Validator, DeepLinkHandler, FeatureFlagManager |
| `SwiftUtilsUIUtilities` | `import SwiftUtilsUIUtilities` | GradientBuilder, gradient presets, UIView extensions |
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
        .product(name: "SwiftUtilsHelpers", package: "swift-utils"),
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

**FeatureFlagManager** — A lightweight, type-safe feature flag system. Define flags as `FeatureFlag<Value>` constants with keys and default values. The manager resolves values through layered lookup: local overrides → registered providers → defaults. Supports change observation with auto-cancelling tokens, a `DictionaryFlagProvider` for testing, and thread-safe concurrent reads with barrier writes. Integrate with remote config services by implementing the `FeatureFlagProvider` protocol.

### UI Utilities

**GradientBuilder** — A declarative, chainable builder for creating `CAGradientLayer` instances. Supports linear gradients with 8 predefined directions (plus custom), radial gradients, configurable corner radii, and rendering to `UIImage`. Includes a `UIView.applyGradient(_:)` extension for one-liner background gradients, plus preset gradients (`.sunset`, `.ocean`, `.forest`, `.nightSky`). Stops are automatically sorted by location.

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
│   │   ├── FeatureFlagManager.swift
│   │   ├── Logger.swift
│   │   └── Validator.swift
│   ├── Networking/
│   │   └── APIClient.swift
│   ├── Storage/
│   │   ├── KeychainWrapper.swift
│   │   └── UserDefaultsWrapper.swift
│   └── UIUtilities/
│       └── GradientBuilder.swift
└── Tests/
    ├── ConcurrencyTests/
    │   └── DebounceThrottleTests.swift
    ├── ExtensionsTests/
    │   ├── ArrayExtensionsTests.swift
    │   ├── DateExtensionsTests.swift
    │   └── StringExtensionsTests.swift
    ├── HelpersTests/
    │   ├── DeepLinkHandlerTests.swift
    │   ├── FeatureFlagManagerTests.swift
    │   ├── LoggerTests.swift
    │   └── ValidatorTests.swift
    ├── NetworkingTests/
    │   └── APIClientTests.swift
    ├── StorageTests/
    │   ├── KeychainWrapperTests.swift
    │   └── UserDefaultsWrapperTests.swift
    └── UIUtilitiesTests/
        └── GradientBuilderTests.swift
```

## License

MIT
