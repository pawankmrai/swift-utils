# StateMachine

A thread-safe, generic finite state machine with declarative routes, guard conditions, enter/exit hooks, and a bounded transition history.

Screens, media players, upload pipelines, and auth sessions all have states — but they're usually modelled with a tangle of `isLoading` / `hasError` / `didFinish` flags that can drift into impossible combinations. `StateMachine` makes the states and the allowed moves between them explicit: you declare routes once, fire events, and invalid transitions are rejected with a typed error instead of silently corrupting state.

## API

| Type / Method | Description |
|---|---|
| `StateMachine<State, Event>(initial:historyLimit:)` | Creates a machine in `initial`, keeping up to `historyLimit` (default 50) past transitions |
| `state: State` | The current state |
| `history: [Transition]` | Completed transitions, oldest first, capped at `historyLimit` |
| `addRoute(from:on:to:guard:)` | Declares a route from one state or an array of states; an optional guard can block it |
| `addRoute(fromAnyOn:to:guard:)` | Wildcard route used from any state without a more specific route for that event |
| `onEnter(_:_:)` | Handler called after entering a state |
| `onExit(_:_:)` | Handler called just before leaving a state |
| `onTransition(_:)` | Handler called after every successful transition |
| `fire(_:) throws -> State` | Performs the transition, runs hooks (exit → enter → transition), returns the new state |
| `tryFire(_:) -> Bool` | Non-throwing variant; returns `false` if the transition was not allowed |
| `canFire(_:) -> Bool` | Whether the event is currently allowed (route exists and guard passes) |
| `destination(for:) -> State?` | Where the event would lead right now, or `nil` |
| `reset(to:)` | Forces a state without running hooks and clears history |
| `Transition` | `from`, `event`, `to` (Equatable) |
| `TransitionError` | `.noRoute(from:event:)`, `.guardRejected(from:event:)` |

## Examples

### Media player

```swift
import SwiftUtilsHelpers

enum PlayerState: Hashable { case idle, loading, playing, paused, failed }
enum PlayerEvent: Hashable { case load, ready, play, pause, fail, stop }

let player = StateMachine<PlayerState, PlayerEvent>(initial: .idle)
player.addRoute(from: .idle, on: .load, to: .loading)
player.addRoute(from: .loading, on: .ready, to: .paused)
player.addRoute(from: .paused, on: .play, to: .playing)
player.addRoute(from: .playing, on: .pause, to: .paused)
player.addRoute(from: [.loading, .playing], on: .fail, to: .failed)
player.addRoute(fromAnyOn: .stop, to: .idle)

try player.fire(.load)   // .loading
try player.fire(.ready)  // .paused
try player.fire(.play)   // .playing

do {
    try player.fire(.load)   // not allowed while playing
} catch let error as StateMachine<PlayerState, PlayerEvent>.TransitionError {
    print(error) // noRoute(from: .playing, event: .load)
}
```

### Driving UI with hooks

```swift
final class PlayerViewController: UIViewController {
    private let machine = StateMachine<PlayerState, PlayerEvent>(initial: .idle)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRoutes()

        machine.onEnter(.loading) { [weak self] _ in self?.spinner.startAnimating() }
        machine.onExit(.loading)  { [weak self] _ in self?.spinner.stopAnimating() }
        machine.onEnter(.failed)  { [weak self] _ in self?.showRetryBanner() }

        machine.onTransition { [weak self] _ in
            guard let self else { return }
            self.playButton.isEnabled = self.machine.canFire(.play)
            self.pauseButton.isEnabled = self.machine.canFire(.pause)
        }
    }

    @IBAction func playTapped() { machine.tryFire(.play) }
    @IBAction func pauseTapped() { machine.tryFire(.pause) }
}
```

### Guards

Guards receive the pending `Transition` and return `false` to block it:

```swift
enum Checkout: Hashable { case cart, shipping, payment, confirmed }
enum Step: Hashable { case next, back }

let cart = CartModel()
let flow = StateMachine<Checkout, Step>(initial: .cart)

flow.addRoute(from: .cart, on: .next, to: .shipping, guard: { _ in !cart.items.isEmpty })
flow.addRoute(from: .shipping, on: .next, to: .payment, guard: { _ in cart.address != nil })
flow.addRoute(from: .payment, on: .next, to: .confirmed)
flow.addRoute(from: .payment, on: .back, to: .shipping)
flow.addRoute(from: .shipping, on: .back, to: .cart)

continueButton.isEnabled = flow.canFire(.next)
```

### Bridging to SwiftUI

```swift
@MainActor
final class UploadViewModel: ObservableObject {
    enum State: Hashable { case idle, uploading, done, failed }
    enum Event: Hashable { case start, succeed, fail, retry }

    @Published private(set) var state: State = .idle
    private let machine = StateMachine<State, Event>(initial: .idle)

    init() {
        machine.addRoute(from: .idle, on: .start, to: .uploading)
        machine.addRoute(from: .uploading, on: .succeed, to: .done)
        machine.addRoute(from: .uploading, on: .fail, to: .failed)
        machine.addRoute(from: .failed, on: .retry, to: .uploading)
        machine.onTransition { [weak self] t in
            Task { @MainActor in self?.state = t.to }
        }
    }

    func upload(_ data: Data) async {
        guard machine.tryFire(.start) || machine.tryFire(.retry) else { return }
        do {
            try await api.upload(data)
            machine.tryFire(.succeed)
        } catch {
            machine.tryFire(.fail)
        }
    }
}
```

### Auto-advancing from a hook

Hooks may fire further events — the lock is recursive, so re-entrant calls are safe:

```swift
machine.onEnter(.loading) { _ in
    if cache.hasMedia { machine.tryFire(.ready) } // skip straight to .paused
}
```

### Debugging with history

```swift
let machine = StateMachine<PlayerState, PlayerEvent>(initial: .idle, historyLimit: 20)
// ... later, attach to a crash report:
let trail = machine.history.map { "\($0.from) --\($0.event)--> \($0.to)" }
logger.error("Player failed. Recent transitions:\n\(trail.joined(separator: "\n"))")
```

### Testing a flow

```swift
func testCheckoutRequiresAddress() {
    let flow = makeCheckoutFlow(cart: CartModel(items: [.sample], address: nil))
    flow.tryFire(.next)                         // cart → shipping
    XCTAssertFalse(flow.canFire(.next))         // blocked by guard
    flow.reset(to: .payment)                    // jump straight to a state under test
    XCTAssertEqual(flow.destination(for: .next), .confirmed)
}
```

## Notes

- Route lookup prefers a specific `(state, event)` route over a wildcard `fromAnyOn` route.
- Re-adding a route for the same `(state, event)` pair replaces the previous one.
- Hooks run synchronously on the thread that called `fire(_:)`, while the machine's lock is held. Hop to the main actor inside hooks for UI work, and avoid blocking on other threads that might fire events on the same machine.
- `reset(to:)` bypasses hooks and clears history — intended for restoration and tests.
