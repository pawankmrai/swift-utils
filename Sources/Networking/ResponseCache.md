# ResponseCache

An actor-based cache for API responses with in-memory and on-disk persistence, plus optional per-entry TTL expiration.

## API

| Type | Description |
|---|---|
| `ResponseCache<Value>` | Actor-based cache for any `Codable & Sendable` value, keyed by `String` |
| `ResponseCache.init(namespace:persistToDisk:defaultTTL:)` | Creates a cache namespaced to its own disk subdirectory |
| `ResponseCache.value(for:)` | Returns the cached value for a key, or `nil` if missing/expired |
| `ResponseCache.value(for:ttl:fetch:)` | Returns the cached value, or runs `fetch`, stores, and returns the fresh result on a miss |
| `ResponseCache.store(_:for:ttl:)` | Stores a value under a key with an optional TTL override |
| `ResponseCache.invalidate(_:)` | Removes a single entry from memory and disk |
| `ResponseCache.removeAll()` | Clears the entire cache (memory and disk) |
| `ResponseCache.evictExpired()` | Evicts all currently-expired entries; returns the number removed |
| `ResponseCache.count` | Number of entries currently held in memory |

## Examples

### Basic store and retrieve

```swift
import SwiftUtilsNetworking

struct UserProfile: Codable, Sendable {
    let id: String
    let name: String
}

let cache = ResponseCache<UserProfile>(namespace: "user-profiles")

await cache.store(profile, for: "user-42", ttl: 300) // expires in 5 minutes
let cached = await cache.value(for: "user-42")        // UserProfile? — nil if expired or missing
```

### Get-or-fetch pattern

The most common usage: check the cache first, fall back to the network on a miss, and cache the result automatically.

```swift
let cache = ResponseCache<UserProfile>(namespace: "user-profiles", defaultTTL: 300)

func loadProfile(id: String) async throws -> UserProfile {
    try await cache.value(for: id) {
        try await apiClient.get("/users/\(id)", as: UserProfile.self)
    }
}
```

### Per-call TTL override

```swift
// Long-lived config — refresh once an hour
let configCache = ResponseCache<AppConfig>(namespace: "app-config")
let config = try await configCache.value(for: "current", ttl: 3600) {
    try await apiClient.get("/config", as: AppConfig.self)
}

// Volatile feed — only cache for 30 seconds
let feed = try await configCache.value(for: "feed", ttl: 30) {
    try await apiClient.get("/feed", as: AppConfig.self)
}
```

### Memory-only cache (no disk persistence)

```swift
let scratch = ResponseCache<SearchResults>(namespace: "search", persistToDisk: false)
await scratch.store(results, for: query)
```

### Invalidating stale data

```swift
// After the user updates their profile, drop the cached copy
await cache.invalidate("user-42")

// Or clear everything, e.g. on logout
await cache.removeAll()
```

### Periodic cleanup

```swift
// Run on a timer or app-foreground event to reclaim memory from expired entries
let evictedCount = await cache.evictExpired()
print("Evicted \(evictedCount) stale entries")
```

### Multiple independent caches

Each `ResponseCache` instance is isolated by `namespace`, so you can run several caches for different response types side by side without key collisions:

```swift
let profiles = ResponseCache<UserProfile>(namespace: "profiles")
let feeds = ResponseCache<[Post]>(namespace: "feeds", defaultTTL: 60)
let config = ResponseCache<AppConfig>(namespace: "config", defaultTTL: 3600)
```
