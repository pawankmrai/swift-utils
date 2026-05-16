# UserDefaultsWrapper

A `@propertyWrapper` for type-safe UserDefaults access with default values, optionals, and custom suites.

## API

| Type | Description |
|---|---|
| `@UserDefault("key", defaultValue:)` | Non-optional property wrapper |
| `@UserDefault("key")` | Optional property wrapper (returns `nil` if unset) |
| `UserDefaultsStorable` | Protocol for supported types |

## Examples

```swift
import SwiftUtilsStorage

struct AppSettings {
    @UserDefault("has_completed_onboarding", defaultValue: false)
    static var hasCompletedOnboarding: Bool

    @UserDefault("username")
    static var username: String?

    @UserDefault("launch_count", defaultValue: 0)
    static var launchCount: Int

    // Custom suite for app groups
    @UserDefault("selected_theme", defaultValue: "light",
                 suite: UserDefaults(suiteName: "group.myapp")!)
    static var selectedTheme: String
}

// Read and write like normal properties
AppSettings.launchCount += 1
AppSettings.username = "Pawan"
AppSettings.hasCompletedOnboarding = true

// Optionals return nil when unset
if let name = AppSettings.username {
    print("Welcome back, \(name)")
}
```
