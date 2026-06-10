# AnalyticsTracker

A thread-safe, protocol-based analytics event tracker that fans events out to one or more backends (Firebase, Amplitude, Mixpanel, custom server, etc.) with built-in global properties, user identity, and session tracking.

## API

| Type / Method | Description |
|---|---|
| `AnalyticsEvent` | Protocol for structured events — define `name` and optional `properties` |
| `AnalyticsBackend` | Protocol to implement for each analytics destination |
| `AnalyticsTracker.shared` | Singleton tracker; or create instances directly |
| `addBackend(_:)` | Register an analytics backend |
| `removeAllBackends()` | Clear all registered backends |
| `set(globalProperty:value:)` | Set (or remove) a property merged into every event |
| `setGlobalProperties(_:)` | Replace the entire global property dictionary |
| `currentGlobalProperties` | Read-only snapshot of current global properties |
| `identify(userId:traits:)` | Associate events with a user identity |
| `reset()` | Clear identity, start a new session; call on sign-out |
| `track(event:)` | Track a structured `AnalyticsEvent` |
| `track(_:properties:)` | Track a freeform event by name |
| `currentSessionId` | Current session UUID, refreshed on `reset()` |
| `trackedEventCount` | Number of events tracked since init or last reset |

## Examples

### 1. Define structured events

```swift
import SwiftUtilsHelpers

struct PurchaseEvent: AnalyticsEvent {
    let name = "purchase_completed"
    let sku: String
    let price: Double

    var properties: [String: Any] {
        ["sku": sku, "price": price, "currency": "USD"]
    }
}

struct ScreenViewEvent: AnalyticsEvent {
    let screenName: String
    var name: String { "screen_view" }
    var properties: [String: Any] { ["screen": screenName] }
}
```

### 2. Implement a backend

```swift
struct ConsoleBackend: AnalyticsBackend {
    func track(event: any AnalyticsEvent, mergedProperties: [String: Any]) {
        print("[Analytics] \(event.name) \(mergedProperties)")
    }
    func identify(userId: String, traits: [String: Any]) {
        print("[Analytics] identify: \(userId) traits: \(traits)")
    }
    func reset() {
        print("[Analytics] reset")
    }
}

// Firebase example
struct FirebaseBackend: AnalyticsBackend {
    func track(event: any AnalyticsEvent, mergedProperties: [String: Any]) {
        // Convert [String: Any] to Firebase-compatible parameters
        // Analytics.logEvent(event.name, parameters: mergedProperties)
    }
    func identify(userId: String, traits: [String: Any]) {
        // Analytics.setUserID(userId)
    }
    func reset() {
        // Analytics.setUserID(nil)
    }
}
```

### 3. Set up the tracker (e.g. in AppDelegate)

```swift
let tracker = AnalyticsTracker.shared

// Register one or more backends
tracker.addBackend(ConsoleBackend())
tracker.addBackend(FirebaseBackend())

// Set properties sent with every event
tracker.set(globalProperty: "appVersion", value: Bundle.main.shortVersion)
tracker.set(globalProperty: "platform", value: "iOS")
```

### 4. Identify a user after sign-in

```swift
tracker.identify(userId: "user_abc123", traits: [
    "email": "pawan@example.com",
    "plan": "pro"
])

// userId is now automatically included in every event
```

### 5. Track events anywhere in the app

```swift
// Structured event
tracker.track(event: PurchaseEvent(sku: "premium_monthly", price: 9.99))

// Freeform event
tracker.track("button_tapped", properties: ["buttonId": "subscribe_cta"])

// Screen view
tracker.track(event: ScreenViewEvent(screenName: "PaywallView"))
```

### 6. Global properties

```swift
// Add per-screen context
tracker.set(globalProperty: "currentScreen", value: "HomeView")

// Remove a property
tracker.set(globalProperty: "currentScreen", value: nil)

// Replace all at once (e.g. after A/B assignment)
tracker.setGlobalProperties([
    "appVersion": "2.1.0",
    "abGroup": "variant_b",
    "locale": Locale.current.identifier
])
```

### 7. Sign-out / session reset

```swift
// Clears userId, resets session ID, zeroes event count
tracker.reset()

print(tracker.currentSessionId)   // new UUID
print(tracker.trackedEventCount)  // 0
```

### 8. Multiple tracker instances

```swift
// Use separate instances for different concerns
let marketingTracker = AnalyticsTracker()
marketingTracker.addBackend(AmplitudeBackend())

let debugTracker = AnalyticsTracker()
debugTracker.addBackend(ConsoleBackend())
```
