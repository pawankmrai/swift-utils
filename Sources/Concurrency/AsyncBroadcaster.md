# AsyncBroadcaster

A multicast channel that fans every sent element out to any number of independent `AsyncStream` subscribers.

A plain `AsyncStream` is single-consumer: if two `for await` loops iterate the same stream, they **split** its elements between them. `AsyncBroadcaster` hands each subscriber its own stream, so every subscriber sees every element — the async/await equivalent of Combine's `PassthroughSubject`, or `CurrentValueSubject` when created with `replay: 1`.

- Send synchronously from any thread, actor, or delegate callback.
- New subscribers can receive the last *N* elements (`replay`) before live ones.
- Subscribers are removed automatically when their task is cancelled or their stream is deallocated.
- `finish()` completes every current subscriber; later subscribers get the replay buffer and end immediately.

## API

| Type / Method | Description |
|---|---|
| `AsyncBroadcaster<Element>(replay:bufferingPolicy:)` | Creates a broadcaster. `replay` (default `0`) is how many recent elements new subscribers receive; `bufferingPolicy` (default `.unbounded`) applies to each subscriber's stream |
| `stream() -> AsyncStream<Element>` | Returns a new, independent subscriber stream |
| `send(_:)` | Delivers an element to all current subscribers and records it for replay. Ignored after `finish()` |
| `finish()` | Completes all subscriber streams. Idempotent; also called on `deinit` |
| `subscriberCount: Int` | Number of active subscribers |
| `isFinished: Bool` | Whether `finish()` has been called |
| `latestValue: Element?` | Most recently sent element (requires `replay > 0`) |
| `BufferingPolicy` | Alias for `AsyncStream<Element>.Continuation.BufferingPolicy` |

## Examples

### Share auth state across features

```swift
enum AuthState: Sendable {
    case signedOut
    case signedIn(userID: String)
}

final class AuthService {
    // replay: 1 → every new subscriber immediately gets the current state.
    let state = AsyncBroadcaster<AuthState>(replay: 1)

    init() { state.send(.signedOut) }

    func signIn(userID: String) { state.send(.signedIn(userID: userID)) }
    func signOut() { state.send(.signedOut) }
}

// Elsewhere — each loop receives every state change independently.
Task { for await s in auth.state.stream() { router.handle(s) } }
Task { for await s in auth.state.stream() { analytics.identify(s) } }
```

### Drive a SwiftUI view with `.task`

```swift
struct CartBadge: View {
    let cart: CartStore
    @State private var count = 0

    var body: some View {
        Image(systemName: "cart")
            .overlay(alignment: .topTrailing) { Text("\(count)").font(.caption2) }
            .task {
                // The subscription ends (and is removed) when the view disappears.
                for await newCount in cart.itemCount.stream() {
                    count = newCount
                }
            }
    }
}

final class CartStore {
    let itemCount = AsyncBroadcaster<Int>(replay: 1)
    private var items: [Item] = [] {
        didSet { itemCount.send(items.count) }
    }
}
```

### Bridge a delegate API to many async consumers

```swift
final class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    let discoveries = AsyncBroadcaster<CBPeripheral>()

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Synchronous send — no Task or await needed in the delegate.
        discoveries.send(peripheral)
    }
}
```

### Only care about the latest value (slow consumers)

```swift
// A heavy renderer that should skip intermediate progress updates.
let progress = AsyncBroadcaster<Double>(bufferingPolicy: .bufferingNewest(1))

Task {
    for await fraction in progress.stream() {
        await renderer.drawExpensiveProgress(fraction)  // never falls behind
    }
}
```

### Event bus with a typed event enum

```swift
enum AppEvent: Sendable {
    case didEnterBackground
    case memoryWarning
    case userDidPurchase(productID: String)
}

let events = AsyncBroadcaster<AppEvent>()

Task {
    for await event in events.stream() {
        if case .memoryWarning = event { imageCache.removeAll() }
    }
}

Task {
    for await event in events.stream() {
        if case let .userDidPurchase(id) = event { await receipts.refresh(for: id) }
    }
}

events.send(.userDidPurchase(productID: "pro.monthly"))
```

### Completing a session

```swift
final class UploadSession {
    let progress = AsyncBroadcaster<Double>(replay: 1)

    func run() async throws {
        defer { progress.finish() }  // every `for await` loop exits cleanly
        for try await fraction in uploader.upload(file) {
            progress.send(fraction)
        }
    }
}

// A late subscriber after completion receives the final value, then ends.
for await last in session.progress.stream() {
    print("Final progress:", last)  // 1.0
}
```

### Inspecting state

```swift
if broadcaster.subscriberCount == 0 {
    sensor.stopUpdates()  // nobody is listening — save power
}

if let current = auth.state.latestValue {
    print("Current auth state:", current)
}
```
