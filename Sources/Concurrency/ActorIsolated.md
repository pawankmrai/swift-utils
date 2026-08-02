# ActorIsolated

A generic, actor-backed box that gives any value — even a non-`Sendable` one — safe, data-race-free access from concurrent contexts.

Swift concurrency requires state that crosses task/thread boundaries to be `Sendable`. Plenty of everyday types — a mutable `struct` accumulator, a legacy reference type, a plain dictionary — aren't, and hand-writing a one-off `actor` wrapper every time is boilerplate. `ActorIsolated<Value>` is that actor, written once and reused everywhere: it serializes every read and write through its own executor, so the wrapped value can never be mutated from two tasks at once.

## API

| Type / Method | Description |
|---|---|
| `ActorIsolated<Value>(_:)` | Wraps a value, taking exclusive ownership of it inside the actor |
| `value: Value` | The current value (async read) |
| `setValue(_:)` | Replaces the wrapped value outright |
| `update(_:) -> Result` | Mutates the value in place via `inout` and returns a result, atomically |
| `withValue(_:) -> Result` | Runs a closure with direct access to the value for atomic read-modify-write |
| `compareAndSet(expected:newValue:) -> Bool` | *(Equatable)* Swaps in `newValue` only if the current value equals `expected` |
| `add(_:) -> Value` | *(AdditiveArithmetic)* Adds `delta` to the value and returns the new total |

## Examples

### Thread-safe counter

```swift
let counter = ActorIsolated(0)

await withTaskGroup(of: Void.self) { group in
    for _ in 0..<100 {
        group.addTask { await counter.update { $0 += 1 } }
    }
}

let total = await counter.value // always 100, never a lost update
```

### Wrapping non-Sendable state for concurrent access

```swift
struct ImageCacheStats {
    var hits = 0
    var misses = 0
}

let stats = ActorIsolated(ImageCacheStats())

func recordHit() async {
    await stats.update { $0.hits += 1 }
}

func recordMiss() async {
    await stats.update { $0.misses += 1 }
}

let snapshot = await stats.value
print("hit rate: \(Double(snapshot.hits) / Double(snapshot.hits + snapshot.misses))")
```

### Atomic "insert if new"

```swift
let seenEventIDs = ActorIsolated<Set<String>>([])

func handle(_ event: AnalyticsEvent) async {
    let isFirstSighting = await seenEventIDs.withValue { ids in
        ids.insert(event.id).inserted
    }
    guard isFirstSighting else { return } // de-duplicate retried deliveries
    await send(event)
}
```

### Compare-and-swap state transitions

```swift
let state = ActorIsolated("idle")

func startIfIdle() async {
    // Only the first caller to observe "idle" wins the transition — safe
    // even if many tasks call this concurrently.
    guard await state.compareAndSet(expected: "idle", newValue: "running") else {
        return // someone else already started it
    }
    await performWork()
    await state.setValue("idle")
}
```

### Accumulating a running total

```swift
let revenue = ActorIsolated(0.0)

await withThrowingTaskGroup(of: Void.self) { group in
    for order in orders {
        group.addTask {
            let amount = try await priceOrder(order)
            _ = await revenue.add(amount)
        }
    }
}

let finalTotal = await revenue.value
```

### Replacing state after an async operation

```swift
let currentUser = ActorIsolated<User?>(nil)

func refreshSession() async throws {
    let user = try await api.fetchCurrentUser()
    await currentUser.setValue(user)
}
```
