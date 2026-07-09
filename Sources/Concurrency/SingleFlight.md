# SingleFlight

Deduplicates concurrent async work so that, no matter how many callers ask for the same thing at once, the underlying operation runs **at most once per key** at any given time.

This is the classic "single-flight" pattern (see Go's `singleflight` package). If five collection view cells all ask for the same user profile within the same frame, or a pull-to-refresh fires while a background prefetch is already loading the same page, only one network request goes out — every other caller simply awaits the result of the request already in flight.

`SingleFlight` does **not** cache completed results. Once a key's operation finishes — successfully or with an error — the next call for that key starts fresh work. Pair it with a cache (e.g. `ResponseCache`) if you also want to remember results after the in-flight window closes.

## API

| Type / Method | Description |
|---|---|
| `SingleFlight<Key, Value>()` | Creates an empty coordinator for a given key and value type |
| `execute(key:operation:) async throws -> Value` | Runs `operation` for `key`, or joins the in-flight call for that key if one exists |
| `isInFlight(_:) -> Bool` | Whether work for `key` is currently running |
| `inFlightCount: Int` | Number of distinct keys with work currently in flight |
| `cancel(_:)` | Cancels the in-flight task for `key`, if any, and forgets it |
| `cancelAll()` | Cancels every in-flight task and clears all tracked keys |

## Examples

### Deduplicate concurrent network requests

```swift
final class ProfileRepository {
    private let flight = SingleFlight<String, UserProfile>()

    // Called from many places at once — cell reuse, prefetch, pull-to-refresh.
    // Only the first caller for a given `id` actually hits the network; the
    // rest await that same request.
    func profile(id: String) async throws -> UserProfile {
        try await flight.execute(key: id) {
            try await api.fetchProfile(id: id)
        }
    }
}
```

### Guard against duplicate submits

```swift
let submitFlight = SingleFlight<String, Void>()

func submitOrder(_ order: Order) async throws {
    // If the user double-taps "Place Order", the second tap joins the
    // first call instead of firing a second POST.
    try await submitFlight.execute(key: order.id) {
        try await api.placeOrder(order)
    }
}
```

### Combine with a TaskGroup for a batch of keys

```swift
let flight = SingleFlight<Int, Thumbnail>()

let thumbnails = try await withThrowingTaskGroup(of: (Int, Thumbnail).self) { group in
    for id in visibleIDs {
        group.addTask {
            let thumb = try await flight.execute(key: id) {
                try await thumbnailService.render(id: id)
            }
            return (id, thumb)
        }
    }
    var results: [Int: Thumbnail] = [:]
    for try await (id, thumb) in group {
        results[id] = thumb
    }
    return results
}
```

### Inspect in-flight state

```swift
let flight = SingleFlight<String, Data>()

if await flight.isInFlight("large-download") {
    showSpinner()
}

let pending = await flight.inFlightCount
statusLabel.text = "\(pending) request(s) in flight"
```

### Cancel on sign-out

```swift
final class SessionController {
    private let flight = SingleFlight<String, UserProfile>()

    func signOut() async {
        // Any in-flight profile fetches immediately throw CancellationError
        // to every awaiting caller instead of completing after logout.
        await flight.cancelAll()
        clearLocalState()
    }
}
```

### Cancel a single key

```swift
let flight = SingleFlight<String, SearchResults>()

func cancelSearch(for query: String) async {
    await flight.cancel(query)
}
```
