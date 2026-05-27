# swift-utils

A growing collection of reusable Swift utilities for iOS development. A new utility is added daily, targeting iOS 15+ / Swift 5.9+.

## Installation

Add the package via Swift Package Manager:

```
https://github.com/pawankmrai/swift-utils.git
```

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pawankmrai/swift-utils.git", branch: "main")
]

.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SwiftUtilsNetworking", package: "swift-utils"),
        .product(name: "SwiftUtilsHelpers", package: "swift-utils"),
    ]
)
```

Import only what you need: `SwiftUtilsExtensions`, `SwiftUtilsNetworking`, `SwiftUtilsStorage`, `SwiftUtilsConcurrency`, `SwiftUtilsHelpers`, `SwiftUtilsUIUtilities`, or `SwiftUtils` for everything.

## Utilities

| Utility | Category | Description | Docs |
|---------|----------|-------------|------|
| String+Extensions | Extensions | Email validation, trimming, truncation, slugify, snake_case | [Examples & API](Sources/Extensions/String+Extensions.md) |
| Array+Extensions | Extensions | Safe subscript, chunking, dedup, grouping, frequencies, key-path sort | [Examples & API](Sources/Extensions/Array+Extensions.md) |
| Date+Extensions | Extensions | Relative formatting, components, arithmetic, ISO 8601, day comparisons | [Examples & API](Sources/Extensions/Date+Extensions.md) |
| APIClient | Networking | Async/await HTTP client with auto JSON coding | [Examples & API](Sources/Networking/APIClient.md) |
| UserDefaultsWrapper | Storage | @propertyWrapper for type-safe UserDefaults | [Examples & API](Sources/Storage/UserDefaultsWrapper.md) |
| KeychainWrapper | Storage | Type-safe Keychain for strings, Data, and Codable | [Examples & API](Sources/Storage/KeychainWrapper.md) |
| DebounceThrottle | Concurrency | Thread-safe debouncer and throttler | [Examples & API](Sources/Concurrency/DebounceThrottle.md) |
| SwiftLogger | Helpers | Leveled logger with categories and pluggable destinations | [Examples & API](Sources/Helpers/Logger.md) |
| Validator | Helpers | Composable input validation with chainable rules | [Examples & API](Sources/Helpers/Validator.md) |
| DeepLinkHandler | Helpers | Declarative URL routing with path params and wildcards | [Examples & API](Sources/Helpers/DeepLinkHandler.md) |
| FeatureFlagManager | Helpers | Type-safe feature flags with overrides and observation | [Examples & API](Sources/Helpers/FeatureFlagManager.md) |
| GradientBuilder | UI Utilities | Chainable gradient builder with presets and UIImage rendering | [Examples & API](Sources/UIUtilities/GradientBuilder.md) |
| Optional+Extensions | Extensions | Unwrapping, chaining, filtering, zipping, and typed defaults for optionals | [Examples & API](Sources/Extensions/Optional+Extensions.md) |
| NotificationScheduler | Helpers | Fluent local notification scheduling with time, calendar, and recurring triggers | [Examples & API](Sources/Helpers/NotificationScheduler.md) |
| HapticFeedbackManager | Helpers | Thread-safe haptic feedback with patterns, presets, and custom intensity | [Examples & API](Sources/Helpers/HapticFeedbackManager.md) |
| DisplayFormatter | Helpers | Number, currency, percentage, file size, duration, ordinal, and compact formatting | [Examples & API](Sources/Helpers/Formatter.md) |
| Color+Extensions | Extensions | Hex init, RGBA/HSBA extraction, lighten/darken, blend, contrast ratio, WCAG checks | [Examples & API](Sources/Extensions/Color+Extensions.md) |

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

