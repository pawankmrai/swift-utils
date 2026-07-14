# AsyncRateLimiter

A token-bucket rate limiter for `async`/`await` code that throttles how **often** an operation may run, rather than how many can run concurrently.

`AsyncSemaphore` caps concurrent access — "no more than N at once." `AsyncRateLimiter` caps frequency — "no more than N per second," even if every previous call has already finished. Tokens refill continuously (not in discrete ticks), so a short burst up to `capacity` is allowed immediately, and the rate smooths out afterward. Reach for this in front of a rate-limited API, an analytics pipe, or any downstream system that enforces its own requests-per-second quota.

Because `AsyncRateLimiter` is an `actor`, it's safe to share across tasks without any extra locking.

## API

| Type / Method | Description |
|---|---|
| `AsyncRateLimiter(capacity: Int, refillInterval: TimeInterval)` | Creates a limiter allowing `capacity` events per `refillInterval` seconds, with an initial burst of `capacity` |
| `maxCapacity: Int` | The bucket's maximum size (burst limit) |
| `availableTokens: Double` | Tokens available right now, after applying owed refill (fractional) |
| `acquire() async throws` | Suspends until a token is available, then consumes one; throws `CancellationError` if cancelled while waiting |
| `acquireIgnoringCancellation() async` | Like `acquire()` but swallows cancellation instead of throwing |
| `tryAcquire() -> Bool` | Consumes a token immediately if available; returns `false` without waiting otherwise |
| `withThrottle(_:) async throws -> T` | Acquires a token, then runs and returns the result of the closure |

## Examples

### Throttle calls to a rate-limited API

```swift
// The upstream API allows 5 requests/second, with no burst tolerance beyond that.
let limiter = AsyncRateLimiter(capacity: 5, refillInterval: 1)

for request in requests {
    try await limiter.acquire()
    try await api.send(request)
}
```

### Allow a burst, then settle into a steady rate

```swift
// Up to 10 events immediately, then 10/second sustained.
let limiter = AsyncRateLimiter(capacity: 10, refillInterval: 1)

func logEvent(_ event: AnalyticsEvent) async {
    try await limiter.acquire()
    await analytics.send(event)
}
```

### Non-blocking check with a fallback

```swift
let limiter = AsyncRateLimiter(capacity: 3, refillInterval: 1)

func sendIfAllowed(_ ping: Ping) async {
    guard await limiter.tryAcquire() else {
        droppedPingCount += 1   // back off instead of queuing
        return
    }
    await socket.send(ping)
}
```

### Wrap an operation with `withThrottle`

```swift
let limiter = AsyncRateLimiter(capacity: 2, refillInterval: 1)

func fetchQuote(for symbol: String) async throws -> Quote {
    try await limiter.withThrottle {
        try await marketDataClient.quote(symbol)
    }
}
```

### Share one limiter across many concurrent tasks

```swift
final class SyncEngine {
    // 20 writes/second to the backend, shared across every sync task.
    private let limiter = AsyncRateLimiter(capacity: 20, refillInterval: 1)

    func syncAll(_ records: [Record]) async {
        await withTaskGroup(of: Void.self) { group in
            for record in records {
                group.addTask {
                    try? await self.limiter.acquire()
                    try? await self.upload(record)
                }
            }
        }
    }

    private func upload(_ record: Record) async throws {
        try await api.put(record)
    }
}
```

### Cancellable wait

```swift
let limiter = AsyncRateLimiter(capacity: 1, refillInterval: 5)
_ = await limiter.tryAcquire() // drain the only token

let task = Task {
    do {
        try await limiter.acquire()
        performThrottledWork()
    } catch is CancellationError {
        // Waiting for the next token was cancelled — nothing was consumed.
    }
}

// Later, if the user navigates away:
task.cancel()
```

### Inspect remaining budget

```swift
let limiter = AsyncRateLimiter(capacity: 5, refillInterval: 1)

func remainingBudget() async -> Int {
    Int(await limiter.availableTokens)
}
```
