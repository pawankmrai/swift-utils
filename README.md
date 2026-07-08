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
| Data+Extensions | Extensions | Hex encoding, URL-safe Base64, SHA-256/MD5 hashing, UTF-8 conversion, JSON pretty-print, compression | [Examples & API](Sources/Extensions/Data+Extensions.md) |
| NetworkRetrier | Networking | Configurable retry with exponential backoff, jitter, and preset policies | [Examples & API](Sources/Networking/NetworkRetrier.md) |
| Int+Extensions | Extensions | Clamping, digits, ordinals, Roman numerals, time intervals, parity, byte formatting, math | [Examples & API](Sources/Extensions/Int+Extensions.md) |
| URL+Extensions | Extensions | Query params, path helpers, deep links, secure check, file type detection, URL masking | [Examples & API](Sources/Extensions/URL+Extensions.md) |
| Collection+Extensions | Extensions | Safe access, partitioning, sum/average, key-path aggregation, inspection helpers | [Examples & API](Sources/Extensions/Collection+Extensions.md) |
| AnimationUtilities | UI Utilities | Declarative chainable animations with presets, sequences, and UIView convenience extensions | [Examples & API](Sources/UIUtilities/AnimationUtilities.md) |
| AppVersionChecker | Helpers | Compare installed vs App Store version using iTunes Lookup API; returns upToDate, updateAvailable, or aheadOfStore | [Examples & API](Sources/Helpers/AppVersionChecker.md) |
| FileManagerHelper | Storage | Type-safe file read/write/move/copy/delete across Documents, Caches, tmp, and custom sandbox directories | [Examples & API](Sources/Storage/FileManagerHelper.md) |
| AsyncTaskQueue | Concurrency | Actor-based queue with configurable concurrency limit, result forwarding, and pending cancellation | [Examples & API](Sources/Concurrency/AsyncTaskQueue.md) |
| AnalyticsTracker | Helpers | Protocol-based analytics tracker with global properties, user identity, session tracking, and multi-backend fan-out | [Examples & API](Sources/Helpers/AnalyticsTracker.md) |
| RequestBuilder | Networking | Fluent chainable URLRequest builder with method, headers, query params, JSON body, timeout, and direct execute/decode | [Examples & API](Sources/Networking/RequestBuilder.md) |
| NetworkMonitor | Networking | Async/await + Combine network connectivity monitor with interface detection and timeout support | [Examples & API](Sources/Networking/NetworkMonitor.md) |
| ResponseCache | Networking | Actor-based response cache with in-memory + disk persistence, TTL expiration, and get-or-fetch | [Examples & API](Sources/Networking/ResponseCache.md) |
| LayoutHelpers | UI Utilities | Chainable Auto Layout builder for pinning edges, centering, sizing, aspect ratio, and dimension matching | [Examples & API](Sources/UIUtilities/LayoutHelpers.md) |
| CoreDataStack | Storage | Generic Core Data stack with typed fetch/save/delete, async background tasks, batch delete, and in-memory mode for tests/previews | [Examples & API](Sources/Storage/CoreDataStack.md) |
| TaskBag | Concurrency | Combine-style cancellation bag for structured-concurrency `Task`s, with auto-removal on completion and cancel-on-deinit | [Examples & API](Sources/Concurrency/TaskBag.md) |
| BiometricAuthManager | Helpers | Async/await Face ID, Touch ID, and Optic ID authentication with typed errors and device-passcode fallback | [Examples & API](Sources/Helpers/BiometricAuthManager.md) |
| PermissionManager | Helpers | Async/await wrapper for camera, microphone, photo library, contacts, and location permissions with unified status checks | [Examples & API](Sources/Helpers/PermissionManager.md) |
| AsyncTimeout | Concurrency | Race an async throwing operation against a timer with `withTimeout`, default-value fallback, and nil-on-timeout variants | [Examples & API](Sources/Concurrency/AsyncTimeout.md) |
| ConcurrentMap | Concurrency | `TaskGroup`-backed concurrent `map`/`forEach`/`compactMap` over sequences with concurrency limits, plus a first-to-finish `ConcurrentRace` helper | [Examples & API](Sources/Concurrency/ConcurrentMap.md) |
| ImageLoader | Networking | Actor-based remote image loader with memory/disk caching, request de-duplication, cancellation, and a cell-reuse-safe UIImageView extension | [Examples & API](Sources/Networking/ImageLoader.md) |
| PaginationController | Networking | Actor-based cursor/page-number pagination controller with concurrent load de-duplication, refresh, and error tracking | [Examples & API](Sources/Networking/PaginationController.md) |
| MultipartFormDataBuilder | Networking | RFC 7578 multipart/form-data builder for file uploads, with JSON parts, disk-backed files, and a URLRequest convenience | [Examples & API](Sources/Networking/MultipartFormDataBuilder.md) |
| CodableStore | Storage | Thread-safe, disk-backed JSON store for `Codable & Identifiable` models with O(1) lookup, predicate queries, batch upsert, and atomic writes | [Examples & API](Sources/Storage/CodableStore.md) |
| AsyncSemaphore | Concurrency | Non-thread-blocking counting semaphore for async/await with FIFO ordering, cancellation, and a scoped `withPermit` helper to cap concurrency | [Examples & API](Sources/Concurrency/AsyncSemaphore.md) |
| ToastPresenter | UI Utilities | Queue-based toast/banner presenter with styles, auto-dismiss, tap and swipe to dismiss | [Examples & API](Sources/UIUtilities/ToastPresenter.md) |
| KeyboardObserver | UI Utilities | Combine/async observer for keyboard height, visibility, and animation timing, with UIScrollView inset adjustment and SwiftUI `.keyboardAdaptive()` modifier | [Examples & API](Sources/UIUtilities/KeyboardObserver.md) |
| PasteboardManager | Helpers | Type-safe UIPasteboard wrapper with expiring items, local-only copies, and change observation | [Examples & API](Sources/Helpers/PasteboardManager.md) |
| ReviewPromptManager | Helpers | Throttled App Store review prompts based on significant events, install age, cooldown, and per-version limits | [Examples & API](Sources/Helpers/ReviewPromptManager.md) |

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

