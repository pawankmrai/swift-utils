# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Latest Addition

### SwiftLogger (Helpers)

A lightweight, structured logging utility with configurable levels and pluggable destinations.

```swift
import SwiftUtilsHelpers

// Use the shared instance
SwiftLogger.shared.info("App launched")
SwiftLogger.shared.error("Request failed", category: "API")

// Or create a custom logger
let log = SwiftLogger(minimumLevel: .warning, destinations: [ConsoleDestination()])
log.warning("Disk space low", category: "Storage")

// Build custom destinations
struct AnalyticsDestination: LogDestination {
    func write(_ entry: LogEntry) {
        // Send to your analytics service
    }
}
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
| `SwiftUtilsStorage` | `import SwiftUtilsStorage` | UserDefaults property wrapper |
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
        .product(name: "SwiftUtilsHelpers", package: "swift-utils"),
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
