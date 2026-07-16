# CloudKeyValueStore

Type-safe iCloud key-value sync via `@CloudStorage`/`@CloudCodableStorage` property wrappers, plus `CloudKeyValueObserver` for reacting to values changed on other devices. Built on `NSUbiquitousKeyValueStore`, capped at 1 MB / 1024 keys — ideal for lightweight preferences, not documents.

## API

| Type | Description |
|---|---|
| `@CloudStorage("key", defaultValue:)` | Property wrapper for `Bool`, `Int`, `Double`, `Float`, `String`, `Data` |
| `@CloudCodableStorage("key", defaultValue:)` | Property wrapper for any `Codable` type, stored as JSON |
| `CloudValueStorable` | Protocol for types supported by `@CloudStorage` |
| `CloudKeyValueStoring` | Protocol abstraction over the store, for testability |
| `CloudStorage.remove()` | Removes the stored value, reverting to the default |
| `CloudStorage.isSet` | `true` if a value is explicitly stored for the key |
| `CloudKeyValueObserver` | Observes external (cross-device) changes to the store |
| `CloudKeyValueObserver.start()` / `.stop()` | Begin/end observing `didChangeExternallyNotification` |
| `CloudKeyValueObserver.onChange` | Closure called with `(reason, changedKeys)` on external change |
| `CloudKeyValueObserver.changes` | `AsyncStream<(ChangeReason, [String])>` alternative to `onChange` |
| `CloudKeyValueObserver.isAvailable` | Static check for whether iCloud is signed in and available |

## Examples

```swift
import SwiftUtilsStorage

struct Preferences {
    @CloudStorage("preferred_units", defaultValue: "metric")
    static var preferredUnits: String

    @CloudStorage("has_seen_tip_jar", defaultValue: false)
    static var hasSeenTipJar: Bool

    @CloudStorage("reader_font_scale", defaultValue: 1.0)
    static var readerFontScale: Double
}

// Read and write like normal properties — writes sync to iCloud automatically
Preferences.preferredUnits = "imperial"
Preferences.hasSeenTipJar = true

// Check whether a value has ever been explicitly set
if !Preferences.$hasSeenTipJar.isSet {
    showTipJarPrompt()
}

// Revert to the default value
Preferences.$preferredUnits.remove()
```

### Storing Codable values

```swift
struct DisplaySettings: Codable {
    var theme: String
    var fontScale: Double
}

struct Preferences {
    @CloudCodableStorage(
        "display_settings",
        defaultValue: DisplaySettings(theme: "system", fontScale: 1.0)
    )
    static var display: DisplaySettings
}

Preferences.display = DisplaySettings(theme: "dark", fontScale: 1.2)
```

### Reacting to changes made on other devices

```swift
let observer = CloudKeyValueObserver()

observer.onChange = { reason, changedKeys in
    guard changedKeys.contains("preferred_units") else { return }
    print("Units changed elsewhere (\(reason)): \(Preferences.preferredUnits)")
    refreshUnitLabels()
}

observer.start()

// ...later, e.g. in deinit or scene teardown
observer.stop()
```

### Using the AsyncStream variant

```swift
Task {
    let observer = CloudKeyValueObserver()
    observer.start()
    for await (reason, keys) in observer.changes {
        print("iCloud sync (\(reason)): \(keys)")
    }
}
```

### Checking availability before relying on sync

```swift
if CloudKeyValueObserver.isAvailable {
    Preferences.preferredUnits = "metric"
} else {
    // Fall back to @UserDefault-only storage; iCloud isn't signed in.
}
```

### Testing with a fake store

```swift
final class InMemoryCloudStore: CloudKeyValueStoring {
    private var storage: [String: Any] = [:]
    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }
    @discardableResult func synchronize() -> Bool { true }
    var dictionaryRepresentation: [String: Any] { storage }
}

var wrapper = CloudStorage<Bool>("flag", defaultValue: false, store: InMemoryCloudStore())
wrapper.wrappedValue = true
XCTAssertTrue(wrapper.wrappedValue)
```
