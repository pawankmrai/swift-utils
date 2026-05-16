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

**String+Extensions** — Common string helpers including email validation, trimming, numeric checks, truncation, slugification, and camelCase-to-snake_case conversion. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Extensions/String%2BExtensions.swift)

```swift
let email = "user@example.com"
print(email.isValidEmail)       // true

let title = "Hello World From Swift"
print(title.slugified)          // "hello-world-from-swift"
print(title.truncated(to: 11))  // "Hello World…"
print("userName".snakeCased)    // "user_name"
```

**Date+Extensions** — Comprehensive date utilities with relative formatting, component access, date arithmetic, ISO 8601 parsing, and day-level comparisons (isToday, isYesterday, etc.). [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Extensions/Date%2BExtensions.swift)

```swift
let yesterday = Date().adding(days: -1)
print(yesterday.relativeString())           // "1 day ago"
print(Date().formatted(as: "MMM d, yyyy")) // "May 16, 2026"
print(Date().isToday)                       // true
print(Date().year)                          // 2026
```

**Array+Extensions** — Safe subscripting, chunking, deduplication (preserving order), grouping by key path, frequency counting, key-path-based min/max/sorted, and more. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Extensions/Array%2BExtensions.swift)

```swift
let items = ["a", "b", "c"]
print(items[safe: 10])                // nil (no crash)

let batches = [1, 2, 3, 4, 5].chunked(into: 2)
// [[1, 2], [3, 4], [5]]

let unique = [1, 2, 2, 3, 1].uniqued()  // [1, 2, 3]
```

### Networking

**APIClient** — A lightweight, async/await-based HTTP client built on URLSession. Supports GET, POST, and other methods with automatic JSON encoding/decoding, configurable headers, and snake_case key strategy. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Networking/APIClient.swift)

```swift
let client = APIClient(baseURL: URL(string: "https://api.example.com")!)

// GET request with automatic decoding
let users: [User] = try await client.get("/users")

// POST request with body
let newUser: User = try await client.post("/users", body: CreateUserRequest(name: "Pawan"))
```

### Storage

**UserDefaultsWrapper** — A `@propertyWrapper` for type-safe UserDefaults access. Supports default values, optional types, and custom suites. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Storage/UserDefaultsWrapper.swift)

```swift
struct AppSettings {
    @UserDefault("has_completed_onboarding", defaultValue: false)
    static var hasCompletedOnboarding: Bool

    @UserDefault("username")
    static var username: String?

    @UserDefault("launch_count", defaultValue: 0)
    static var launchCount: Int
}

AppSettings.launchCount += 1
```

**KeychainWrapper** — A type-safe wrapper around the iOS Keychain Services API. Securely store, retrieve, and delete strings, Data, or any Codable type. Supports configurable accessibility levels and access groups. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Storage/KeychainWrapper.swift)

```swift
let keychain = KeychainWrapper()

// Store and retrieve a string
try keychain.set("s3cret_token", forKey: "auth_token")
let token: String? = try keychain.string(forKey: "auth_token")

// Store a Codable object
try keychain.set(credentials, forKey: "user_credentials")
let saved: Credentials? = try keychain.object(forKey: "user_credentials")
```

### Concurrency

**DebounceThrottle** — Thread-safe `Debouncer` and `Throttler` classes for rate-limiting closure execution. The debouncer waits for a quiet period before firing; the throttler caps execution frequency with leading, trailing, or both modes. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Concurrency/DebounceThrottle.swift)

```swift
// Debounce search input — fires 0.3s after the user stops typing
let debouncer = Debouncer(delay: 0.3)
debouncer.debounce {
    viewModel.search(query: textField.text ?? "")
}

// Throttle scroll events — fires at most once per 0.5s
let throttler = Throttler(interval: 0.5, mode: .leadingAndTrailing)
throttler.throttle {
    updateParallaxEffect()
}
```

### Helpers

**SwiftLogger** — A configurable, thread-safe logger with severity levels (verbose through fatal), category tagging, and pluggable destinations. Uses `os.Logger` in release and `print` in debug. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Helpers/Logger.swift)

```swift
let log = SwiftLogger(subsystem: "com.myapp", category: "Networking")
log.info("Request started for /users")
log.error("Failed to decode response: \(error)")

// Filter by minimum level
log.minimumLevel = .warning  // silences verbose/debug/info
```

**Validator** — A composable, type-safe input validation framework. Chain rules like `.nonEmpty()`, `.email()`, `.minLength(_:)`, `.strongPassword()`, or custom predicates. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Helpers/Validator.swift)

```swift
let emailValidator = Validator<String>()
    .add(.nonEmpty(message: "Email is required"))
    .add(.email())

let errors = emailValidator.errors(for: "not-an-email")
// ["Value is not a valid email address"]

let passwordValidator = Validator<String>()
    .add(.minLength(8))
    .add(.strongPassword())
```

**DeepLinkHandler** — A declarative deep link routing system. Register URL patterns with named parameters (`:id`) and wildcards (`*`), then route incoming URLs to handlers with extracted path and query parameters. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Helpers/DeepLinkHandler.swift)

```swift
let router = DeepLinkHandler()

router.register("product/:id") { context in
    let productId = context.pathParameters["id"]!
    showProduct(productId)
}

let url = URL(string: "myapp://product/42?ref=push")!
router.handle(url)  // Routes with id="42", queryParams=["ref": "push"]
```

**FeatureFlagManager** — A lightweight, type-safe feature flag system with layered value resolution (local overrides, providers, defaults), change observation, and a `DictionaryFlagProvider` for testing. [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/Helpers/FeatureFlagManager.swift)

```swift
extension FeatureFlag {
    static let newOnboarding = FeatureFlag<Bool>(key: "new_onboarding", defaultValue: false)
}

let manager = FeatureFlagManager.shared

if manager.isEnabled(.newOnboarding) {
    showNewOnboarding()
}

// Override for testing or debug menus
manager.setOverride(true, for: .newOnboarding)

// Observe changes
let token = manager.observe(.newOnboarding) { change in
    print("Changed: \(change.oldValue) → \(change.newValue)")
}
```

### UI Utilities

**GradientBuilder** — A declarative, chainable builder for `CAGradientLayer`. Supports linear and radial gradients, 8 predefined directions, rendering to UIImage, and preset gradients (.sunset, .ocean, .forest, .nightSky). [View Source](https://github.com/pawankmrai/swift-utils/blob/main/Sources/UIUtilities/GradientBuilder.swift)

```swift
// Chainable gradient
let layer = GradientBuilder()
    .add(color: .systemBlue, at: 0)
    .add(color: .systemPurple, at: 1)
    .direction(.leftToRight)
    .cornerRadius(16)
    .build(in: view.bounds)

// One-liner on a view
view.applyGradient(GradientBuilder.sunset)

// Render to image
let image = GradientBuilder.ocean.renderImage(size: CGSize(width: 300, height: 200))
```

## License

MIT
