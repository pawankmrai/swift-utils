# FeatureFlagManager

A type-safe feature flag system with layered resolution, local overrides, provider protocol, and change observation.

## API

| Type / Method | Description |
|---|---|
| `FeatureFlag<Value>(key:defaultValue:)` | Define a typed flag |
| `value(for:)` | Resolve a flag's current value |
| `isEnabled(_:)` | Convenience for `Bool` flags |
| `setOverride(_:for:)` | Set a local override (highest priority) |
| `removeOverride(for:)` | Revert to provider/default |
| `observe(_:callback:)` | Watch for value changes |
| `registerProvider(_:)` | Add a remote flag source |
| `DictionaryFlagProvider` | Simple dictionary-backed provider |

### Resolution Order

1. Local overrides (via `setOverride`)
2. Registered providers (in registration order)
3. Flag's default value

## Examples

```swift
import SwiftUtilsHelpers

// Define flags as static constants
extension FeatureFlag {
    static let newOnboarding = FeatureFlag<Bool>(key: "new_onboarding", defaultValue: false)
    static let maxRetries = FeatureFlag<Int>(key: "max_retries", defaultValue: 3)
    static let welcomeMsg = FeatureFlag<String>(key: "welcome_msg", defaultValue: "Hello!")
}

let manager = FeatureFlagManager.shared

// Read flags
if manager.isEnabled(.newOnboarding) {
    showNewOnboarding()
}
let retries = manager.value(for: .maxRetries)  // 3

// Local override — great for debug menus
manager.setOverride(true, for: .newOnboarding)
manager.isEnabled(.newOnboarding)  // true

// Remove override to revert
manager.removeOverride(for: .newOnboarding)

// Observe changes
let token = manager.observe(.newOnboarding) { change in
    print("\(change.oldValue) → \(change.newValue)")
}
// token auto-cancels on dealloc, or call token.cancel()

// Register a remote provider (e.g., from a JSON config)
let remoteFlags = DictionaryFlagProvider(values: [
    "new_onboarding": true,
    "max_retries": 5
])
manager.registerProvider(remoteFlags)

// Implement FeatureFlagProvider for Firebase, LaunchDarkly, etc.
class FirebaseProvider: FeatureFlagProvider {
    func value<V: Codable>(forKey key: String, type: V.Type) -> V? {
        // Fetch from RemoteConfig...
    }
}
```
