import Foundation

/// A thread-safe, generic finite state machine with declarative routes,
/// guard conditions, enter/exit hooks, and a bounded transition history.
///
/// Model screen flows, player states, upload pipelines, or auth sessions as
/// explicit `State` / `Event` enums instead of scattered boolean flags.
///
/// ```swift
/// enum Player: Hashable { case idle, playing, paused }
/// enum Action: Hashable { case play, pause, stop }
///
/// let machine = StateMachine<Player, Action>(initial: .idle)
/// machine.addRoute(from: [.idle, .paused], on: .play, to: .playing)
/// machine.addRoute(from: .playing, on: .pause, to: .paused)
/// machine.addRoute(fromAnyOn: .stop, to: .idle)
/// try machine.fire(.play) // .playing
/// ```
public final class StateMachine<State: Hashable, Event: Hashable>: @unchecked Sendable {

    /// A single state change triggered by an event.
    public struct Transition: Equatable {
        public let from: State
        public let event: Event
        public let to: State
    }

    /// Errors thrown by ``fire(_:)``.
    public enum TransitionError: Error, Equatable {
        /// No route exists for `event` while in `from`.
        case noRoute(from: State, event: Event)
        /// A route exists but its guard returned `false`.
        case guardRejected(from: State, event: Event)
    }

    /// Return `false` to block a transition.
    public typealias Guard = (Transition) -> Bool
    /// Called with a completed (or pending, for exit hooks) transition.
    public typealias Handler = (Transition) -> Void

    private struct RouteKey: Hashable { let from: State?; let event: Event }
    private struct Route { let to: State; let condition: Guard? }

    private let lock = NSRecursiveLock()
    private var _state: State
    private var routes: [RouteKey: Route] = [:]
    private var enterHandlers: [State: [Handler]] = [:]
    private var exitHandlers: [State: [Handler]] = [:]
    private var transitionHandlers: [Handler] = []
    private var _history: [Transition] = []

    /// Maximum number of transitions kept in ``history``. `0` disables history.
    public let historyLimit: Int

    /// Creates a state machine.
    /// - Parameters:
    ///   - initial: The starting state.
    ///   - historyLimit: How many past transitions to retain (default 50).
    public init(initial: State, historyLimit: Int = 50) {
        self._state = initial
        self.historyLimit = max(0, historyLimit)
    }

    /// The current state.
    public var state: State { lock.synchronized { _state } }

    /// Most-recent-last list of completed transitions, capped at ``historyLimit``.
    public var history: [Transition] { lock.synchronized { _history } }

    // MARK: - Configuration

    /// Adds a route from each state in `sources` to `destination` when `event` fires.
    /// Re-adding the same `(from, event)` pair replaces the previous route.
    public func addRoute(from sources: [State], on event: Event, to destination: State, guard condition: Guard? = nil) {
        lock.synchronized {
            for source in sources {
                routes[RouteKey(from: source, event: event)] = Route(to: destination, condition: condition)
            }
        }
    }

    /// Adds a route from a single state.
    public func addRoute(from source: State, on event: Event, to destination: State, guard condition: Guard? = nil) {
        addRoute(from: [source], on: event, to: destination, guard: condition)
    }

    /// Adds a wildcard route that applies from any state lacking a specific route for `event`.
    public func addRoute(fromAnyOn event: Event, to destination: State, guard condition: Guard? = nil) {
        lock.synchronized { routes[RouteKey(from: nil, event: event)] = Route(to: destination, condition: condition) }
    }

    /// Registers a handler invoked after entering `state`.
    public func onEnter(_ state: State, _ handler: @escaping Handler) {
        lock.synchronized { enterHandlers[state, default: []].append(handler) }
    }

    /// Registers a handler invoked just before leaving `state`.
    public func onExit(_ state: State, _ handler: @escaping Handler) {
        lock.synchronized { exitHandlers[state, default: []].append(handler) }
    }

    /// Registers a handler invoked after every successful transition.
    public func onTransition(_ handler: @escaping Handler) {
        lock.synchronized { transitionHandlers.append(handler) }
    }

    // MARK: - Firing

    /// Returns the destination `event` would lead to, or `nil` if it is not currently allowed.
    public func destination(for event: Event) -> State? {
        lock.synchronized {
            guard let route = route(for: event, from: _state) else { return nil }
            let transition = Transition(from: _state, event: event, to: route.to)
            return (route.condition?(transition) ?? true) ? route.to : nil
        }
    }

    /// `true` if firing `event` now would succeed.
    public func canFire(_ event: Event) -> Bool { destination(for: event) != nil }

    /// Fires `event`, moving to the routed state and invoking exit → enter → transition hooks.
    /// - Returns: The new state.
    /// - Throws: ``TransitionError`` when no route exists or a guard rejects it.
    @discardableResult
    public func fire(_ event: Event) throws -> State {
        lock.lock()
        defer { lock.unlock() }
        let current = _state
        guard let route = route(for: event, from: current) else {
            throw TransitionError.noRoute(from: current, event: event)
        }
        let transition = Transition(from: current, event: event, to: route.to)
        guard route.condition?(transition) ?? true else {
            throw TransitionError.guardRejected(from: current, event: event)
        }
        exitHandlers[current]?.forEach { $0(transition) }
        _state = route.to
        if historyLimit > 0 {
            _history.append(transition)
            if _history.count > historyLimit { _history.removeFirst(_history.count - historyLimit) }
        }
        enterHandlers[route.to]?.forEach { $0(transition) }
        transitionHandlers.forEach { $0(transition) }
        return route.to
    }

    /// Fires `event` and returns `false` instead of throwing when it is not allowed.
    @discardableResult
    public func tryFire(_ event: Event) -> Bool { (try? fire(event)) != nil }

    /// Forces the machine into `state` without running hooks, and clears history.
    public func reset(to state: State) {
        lock.synchronized { _state = state; _history.removeAll() }
    }

    private func route(for event: Event, from state: State) -> Route? {
        routes[RouteKey(from: state, event: event)] ?? routes[RouteKey(from: nil, event: event)]
    }
}

private extension NSRecursiveLock {
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
