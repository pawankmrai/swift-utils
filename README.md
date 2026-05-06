# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Utilities

### Extensions

**String+Extensions** — Common string helpers including email validation, trimming, numeric checks, truncation, slugification, and camelCase-to-snake_case conversion.

### Networking

**APIClient** — A lightweight, async/await-based HTTP client built on URLSession. Supports GET, POST, and other methods with automatic JSON encoding/decoding, configurable headers, and snake_case key strategy out of the box.

### Storage

**UserDefaultsWrapper** — A `@propertyWrapper` for type-safe UserDefaults access. Supports default values, optional types, and custom suites. Drop it on a static property and read/write UserDefaults without string-key typos.

### Concurrency

**DebounceThrottle** — Thread-safe `Debouncer` and `Throttler` classes for rate-limiting closure execution. The debouncer waits for a quiet period before firing (ideal for search-as-you-type). The throttler caps execution frequency with `.leading`, `.trailing`, or `.leadingAndTrailing` modes (ideal for scroll handlers and analytics events).

## Structure

```
Sources/
├── Extensions/       # Swift type extensions
├── Networking/       # HTTP & API helpers
├── Storage/          # UserDefaults, Keychain, file helpers
├── Concurrency/      # Async/await, debounce/throttle utilities
├── Helpers/          # General-purpose helpers
└── UI/               # UIKit/SwiftUI helpers
Tests/
├── StringExtensionsTests.swift
├── APIClientTests.swift
├── UserDefaultsWrapperTests.swift
└── DebounceThrottleTests.swift
```

## Usage

Each utility is self-contained and can be dropped into any Swift project, or add the whole package via Swift Package Manager.

## License

MIT
