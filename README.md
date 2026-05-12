# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Latest Addition

### Validator (Helpers)

A composable, type-safe input validation framework. Chain multiple rules to validate form fields, API parameters, or any user input — collect all errors at once or short-circuit on the first failure.

```swift
import SwiftUtilsHelpers

// Build a reusable email validator
let emailValidator = Validator<String>()
    .adding(.nonEmpty(message: "Email is required"))
    .adding(.email())

emailValidator.isValid("user@example.com")  // true
emailValidator.errors(for: "bad")           // ["Must be a valid email address"]

// Password strength check
let passwordValidator = Validator<String>()
    .adding(.minLength(8))
    .adding(.strongPassword())

passwordValidator.firstError(for: "weak")
// .invalid(reason: "Must be at least 8 characters")

// Numeric range validation
let ageRule = ValidationRule<Int>.range(18...120, message: "Invalid age")
ageRule.validate(25)  // .valid

// Custom predicate
let even = ValidationRule<Int>.predicate("Must be even") { $0 % 2 == 0 }
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
| `SwiftUtilsHelpers` | `import SwiftUtilsHelpers` | Logger, Validator |
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
