# CircuitBreaker

An actor-based circuit breaker that stops hammering a failing dependency and gives it time to recover.

Retries help with transient blips, but when a backend is truly down they make things worse: every screen keeps firing requests that time out, draining battery and piling load onto a struggling server. `CircuitBreaker` tracks consecutive failures and, once a threshold is hit, **opens** — rejecting calls instantly with `CircuitBreakerError.circuitOpen(retryAfter:)`. After `resetTimeout` it goes **half-open** and lets a few trial calls through; success closes the circuit, failure re-opens it.

```
closed ──(N failures)──▶ open ──(resetTimeout)──▶ halfOpen ──(successes)──▶ closed
                           ▲                          │
                           └────────(any failure)─────┘
```

## API

| Type / Method | Description |
|---|---|
| `CircuitBreaker(configuration:isFailure:now:)` | Creates a breaker; `isFailure` filters which errors count (ignores `CancellationError` by default); `now` is an injectable clock |
| `CircuitBreaker.Configuration` | `failureThreshold` (5), `resetTimeout` (30s), `successThreshold` (1), `halfOpenMaxCalls` (1) |
| `CircuitBreaker.State` | `.closed`, `.open(until: Date)`, `.halfOpen` |
| `execute(_:) async throws -> T` | Runs an async operation through the breaker, recording success/failure |
| `state: State` | Current state (lazily moves an expired `open` to `halfOpen`) |
| `consecutiveFailures: Int` | Failures counted while closed |
| `onStateChange(_:)` | Registers an observer called on every transition |
| `trip()` | Forces the breaker open for one `resetTimeout` |
| `reset()` | Forces the breaker closed and clears counters |
| `CircuitBreakerError.circuitOpen(retryAfter:)` | Thrown when a call is rejected; `retryAfter` is seconds until a trial is allowed |

## Examples

### Guarding an API endpoint

```swift
let searchBreaker = CircuitBreaker(
    configuration: .init(failureThreshold: 3, resetTimeout: 20)
)

func search(_ query: String) async throws -> [Product] {
    try await searchBreaker.execute {
        try await apiClient.get("/search", query: ["q": query])
    }
}
```

### Showing a friendly fallback when the circuit is open

```swift
do {
    products = try await search(text)
} catch CircuitBreakerError.circuitOpen(let retryAfter) {
    banner = "Search is temporarily unavailable. Try again in \(Int(retryAfter.rounded(.up)))s."
    products = cachedProducts
} catch {
    banner = error.localizedDescription
}
```

### Only counting server-side failures

Client errors (400/404) are the caller's fault and shouldn't trip the breaker; network outages and 5xx should.

```swift
let breaker = CircuitBreaker(
    configuration: .init(failureThreshold: 5, resetTimeout: 60),
    isFailure: { error in
        if error is CancellationError { return false }
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        if case APIError.http(let status, _) = error { return status >= 500 }
        return false
    }
)
```

### Combining with retries

Put the breaker *outside* the retrier so an open circuit short-circuits the whole retry loop instead of each attempt.

```swift
let value = try await breaker.execute {
    try await NetworkRetrier.execute(policy: .conservative) {
        try await apiClient.fetchFeed()
    }
}
```

### Requiring several healthy trial calls before closing

```swift
let paymentsBreaker = CircuitBreaker(
    configuration: .init(
        failureThreshold: 2,
        resetTimeout: 45,
        successThreshold: 3,   // three good calls before trusting it again
        halfOpenMaxCalls: 1    // but only one trial in flight at a time
    )
)
```

### Observing state for logging or UI

```swift
await breaker.onStateChange { state in
    switch state {
    case .open(let until): logger.warning("Feed circuit OPEN until \(until)")
    case .halfOpen:        logger.info("Feed circuit probing…")
    case .closed:          logger.info("Feed circuit recovered")
    }
}
```

### Manual control from server signals

```swift
// Backend returned a maintenance header — stop calling for a while.
if response.value(forHTTPHeaderField: "X-Maintenance") == "1" {
    await breaker.trip()
}

// User tapped "Retry now" — give it another chance immediately.
await breaker.reset()
```

### Deterministic tests with an injected clock

```swift
final class TestClock: @unchecked Sendable {
    var now = Date()
}

let clock = TestClock()
let breaker = CircuitBreaker(configuration: .init(failureThreshold: 1, resetTimeout: 10),
                             now: { clock.now })

_ = try? await breaker.execute { throw URLError(.timedOut) }
XCTAssertEqual(await breaker.state, .open(until: clock.now + 10))

clock.now += 10
XCTAssertEqual(await breaker.state, .halfOpen)
```

## Notes

- Results from calls that started before a state transition (e.g. a slow request that finishes after the circuit opened) are ignored, so stale outcomes never corrupt the new state.
- Use one breaker per dependency (per host or per endpoint group) rather than one global breaker.
- Observers run on the breaker's actor; hop to `MainActor` inside them before touching UI.
