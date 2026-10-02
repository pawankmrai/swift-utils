//
//  CircuitBreaker.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-10-02.
//

import Foundation

/// An actor-based circuit breaker that stops calling a failing dependency
/// (e.g. a flaky backend endpoint) until it has had time to recover.
///
/// States:
/// - `closed`: calls flow through; consecutive failures are counted.
/// - `open`: calls fail fast with ``CircuitBreakerError/circuitOpen(retryAfter:)``
///   until `resetTimeout` elapses.
/// - `halfOpen`: a limited number of trial calls are allowed. Enough successes
///   close the circuit; any failure re-opens it.
public actor CircuitBreaker {

    /// The current state of the breaker.
    public enum State: Equatable, Sendable {
        case closed
        case open(until: Date)
        case halfOpen
    }

    /// Tuning parameters for a ``CircuitBreaker``.
    public struct Configuration: Sendable {
        /// Consecutive failures in `closed` state that trip the breaker.
        public var failureThreshold: Int
        /// How long the breaker stays `open` before allowing trial calls.
        public var resetTimeout: TimeInterval
        /// Successful trial calls in `halfOpen` required to close the breaker.
        public var successThreshold: Int
        /// Maximum concurrent trial calls allowed while `halfOpen`.
        public var halfOpenMaxCalls: Int

        public init(failureThreshold: Int = 5,
                    resetTimeout: TimeInterval = 30,
                    successThreshold: Int = 1,
                    halfOpenMaxCalls: Int = 1) {
            self.failureThreshold = max(1, failureThreshold)
            self.resetTimeout = max(0, resetTimeout)
            self.successThreshold = max(1, successThreshold)
            self.halfOpenMaxCalls = max(1, halfOpenMaxCalls)
        }
    }

    /// The breaker's configuration.
    public let configuration: Configuration
    /// Current state. Reading it lazily transitions an expired `open` to `halfOpen`.
    public var state: State { refreshState(); return _state }
    /// Consecutive failures recorded while `closed`.
    public private(set) var consecutiveFailures = 0

    private var _state: State = .closed
    private var halfOpenSuccesses = 0
    private var halfOpenInFlight = 0
    /// Bumped on every transition so late results from a previous state are ignored.
    private var generation = 0
    private let now: @Sendable () -> Date
    private let isFailure: @Sendable (Error) -> Bool
    private var observers: [@Sendable (State) -> Void] = []

    /// Creates a circuit breaker.
    /// - Parameters:
    ///   - configuration: Thresholds and timeouts.
    ///   - isFailure: Decides whether a thrown error counts against the breaker.
    ///     Defaults to counting everything except `CancellationError`.
    ///   - now: Clock source, injectable for tests.
    public init(configuration: Configuration = .init(),
                isFailure: @escaping @Sendable (Error) -> Bool = { !($0 is CancellationError) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.isFailure = isFailure
        self.now = now
    }

    /// Runs `operation` through the breaker.
    /// - Throws: ``CircuitBreakerError/circuitOpen(retryAfter:)`` when the call is
    ///   rejected, otherwise rethrows the operation's error.
    public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try acquirePermit()
        let startGeneration = generation
        do {
            let value = try await operation()
            if generation == startGeneration { recordSuccess() }
            return value
        } catch {
            if generation == startGeneration { recordResult(error: error) }
            throw error
        }
    }

    /// Registers a closure invoked on every state transition.
    public func onStateChange(_ observer: @escaping @Sendable (State) -> Void) {
        observers.append(observer)
    }

    /// Forces the breaker back to `closed` and clears all counters.
    public func reset() {
        consecutiveFailures = 0
        transition(to: .closed)
    }

    /// Forces the breaker `open` for one `resetTimeout` (e.g. on a server "maintenance" signal).
    public func trip() {
        transition(to: .open(until: now().addingTimeInterval(configuration.resetTimeout)))
    }

    // MARK: - Internals

    private func acquirePermit() throws {
        refreshState()
        switch _state {
        case .closed:
            return
        case .open(let until):
            throw CircuitBreakerError.circuitOpen(retryAfter: max(0, until.timeIntervalSince(now())))
        case .halfOpen:
            guard halfOpenInFlight < configuration.halfOpenMaxCalls else {
                throw CircuitBreakerError.circuitOpen(retryAfter: 0)
            }
            halfOpenInFlight += 1
        }
    }

    private func recordSuccess() {
        switch _state {
        case .closed:
            consecutiveFailures = 0
        case .halfOpen:
            halfOpenInFlight = max(0, halfOpenInFlight - 1)
            halfOpenSuccesses += 1
            if halfOpenSuccesses >= configuration.successThreshold { reset() }
        case .open:
            break
        }
    }

    private func recordResult(error: Error) {
        let counts = isFailure(error)
        switch _state {
        case .closed:
            guard counts else { return }
            consecutiveFailures += 1
            if consecutiveFailures >= configuration.failureThreshold { trip() }
        case .halfOpen:
            halfOpenInFlight = max(0, halfOpenInFlight - 1)
            if counts { trip() }
        case .open:
            break
        }
    }

    private func refreshState() {
        if case .open(let until) = _state, now() >= until {
            transition(to: .halfOpen)
        }
    }

    private func transition(to newState: State) {
        guard newState != _state else { return }
        _state = newState
        halfOpenSuccesses = 0
        halfOpenInFlight = 0
        generation &+= 1
        observers.forEach { $0(newState) }
    }
}

/// Errors produced by ``CircuitBreaker``.
public enum CircuitBreakerError: Error, Equatable, Sendable {
    /// The call was rejected without running. `retryAfter` is the number of
    /// seconds until the breaker will allow a trial call (0 if trial slots are busy).
    case circuitOpen(retryAfter: TimeInterval)
}
