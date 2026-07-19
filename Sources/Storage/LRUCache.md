# LRUCache

A thread-safe, in-memory **Least-Recently-Used** cache with a fixed capacity and optional per-entry time-to-live (TTL).

`LRUCache` is a general-purpose in-memory cache for any `Key`/`Value` pair — decoded models, computed layout metrics, thumbnail bitmaps, parsed JSON, or anything expensive to recompute but cheap to hold in memory for a while. It's distinct from `CodableStore` (disk-backed persistence) and `ResponseCache` (network-response focused): `LRUCache` never touches disk and has no notion of an HTTP request.

When the cache is full, inserting a new entry evicts the **least recently used** one first. Reading a value counts as a use and promotes that entry to most-recently-used, so hot entries naturally survive while cold ones get evicted. Entries can optionally expire after a `defaultTTL` (set at init) or a per-entry TTL — expired entries are treated as absent and lazily purged on access.

Implemented as an `actor`, so every operation is automatically serialized — safe to share across concurrent callers without any external locking.

## API

| Type / Method | Description |
|---|---|
| `LRUCache<Key, Value>(capacity: Int, defaultTTL: TimeInterval? = nil, clock: @Sendable () -> Date = Date.init)` | Creates a cache with a max entry count, optional default expiration, and an injectable clock for testing |
| `capacity: Int` | Current maximum entry count (read-only; use `setCapacity(_:)` to change) |
| `defaultTTL: TimeInterval?` | Default expiration applied to entries without their own TTL |
| `count: Int` | Number of live (non-expired) entries currently stored |
| `value(forKey:) async -> Value?` | Returns the value for `key`, or `nil` if absent/expired; promotes it to most-recently-used |
| `contains(_:) async -> Bool` | Whether `key` is present and not expired, without affecting recency order |
| `allValues() async -> [Value]` | All non-expired values, ordered most- to least-recently-used |
| `setValue(_:forKey:ttl:) async -> Value?` | Inserts/updates a value, promoting it to MRU; evicts LRU entry if over capacity; returns the evicted value, if any |
| `removeValue(forKey:) async -> Value?` | Removes and returns the value for `key`, if present |
| `removeAll() async` | Removes every entry |
| `setCapacity(_:) async` | Changes the max capacity, evicting LRU entries immediately if shrinking |
| `purgeExpired() async` | Removes all expired entries proactively (e.g. on a memory warning) |

## Examples

### Basic usage

```swift
let cache = LRUCache<URL, UIImage>(capacity: 100)

await cache.setValue(image, forKey: url)

if let cached = await cache.value(forKey: url) {
    imageView.image = cached
} else {
    imageView.image = try await downloadAndDecode(url)
}
```

### Caching expensive computed values

```swift
final class LayoutEngine {
    private let cache = LRUCache<String, CGSize>(capacity: 200)

    func measuredSize(for text: String, font: UIFont) async -> CGSize {
        let key = "\(text)|\(font.fontName)|\(font.pointSize)"
        if let cached = await cache.value(forKey: key) {
            return cached
        }
        let size = (text as NSString).size(withAttributes: [.font: font])
        await cache.setValue(size, forKey: key)
        return size
    }
}
```

### Expiring entries with a default TTL

```swift
// Session tokens are cached for 5 minutes, then must be re-fetched.
let tokenCache = LRUCache<String, AuthToken>(capacity: 10, defaultTTL: 300)

func token(for userID: String) async throws -> AuthToken {
    if let cached = await tokenCache.value(forKey: userID) {
        return cached
    }
    let fresh = try await authService.fetchToken(userID: userID)
    await tokenCache.setValue(fresh, forKey: userID)
    return fresh
}
```

### Per-entry TTL override

```swift
let cache = LRUCache<String, Data>(capacity: 50, defaultTTL: 3600)

// Most entries live an hour, but this one should refresh much sooner.
await cache.setValue(volatileData, forKey: "live-quote", ttl: 5)
await cache.setValue(staticData, forKey: "app-config") // uses the default TTL
```

### Reacting to eviction

```swift
let imageCache = LRUCache<String, UIImage>(capacity: 20)

if let evicted = await imageCache.setValue(newImage, forKey: id) {
    print("Evicted image for a cold key to make room for \(id)")
}
```

### Shrinking capacity under memory pressure

```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { _ in
    Task {
        await imageCache.setCapacity(10)   // evicts down to the new limit
        await imageCache.purgeExpired()
    }
}
```

### Snapshotting cache contents

```swift
let recentQueries = await searchCache.allValues() // most-recently-used first
print("Warm cache has \(recentQueries.count) entries; top hit: \(recentQueries.first ?? "none")")
```
