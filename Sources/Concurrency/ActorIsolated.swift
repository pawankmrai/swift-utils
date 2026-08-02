//
//  ActorIsolated.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-08-02.
//

import Foundation

// MARK: - ActorIsolated

/// A generic, actor-backed box that gives any (even non-`Sendable`) value
/// safe, data-race-free access from concurrent contexts.
///
/// Swift concurrency requires state that crosses task/thread boundaries to
/// be `Sendable`. Plenty of everyday types — a mutable `struct` accumulator,
/// a legacy reference type, a plain `[String: Any]` — aren't, and wrapping
/// them in a bespoke `actor` every time is boilerplate. `ActorIsolated<T>`
/// is that actor, written once and reused everywhere: it serializes every
/// read and write through its own executor, so the wrapped value can never
/// be mutated from two tasks at the same time.
///
/// ```swift
/// let counter = ActorIsolated(0)
///
/// await withTaskGroup(of: Void.self) { group in
///     for _ in 0..<100 {
///         group.addTask { await counter.update { $0 += 1 } }
///     }
/// }
///
/// let total = await counter.value // always 100, never a lost update
/// ```
///
/// For simple numeric counters prefer ``update(_:)``'s return value or
/// ``value``; for compound state, pass a closure to ``withValue(_:)`` to
/// perform several reads/writes atomically in one hop to the actor.
public actor ActorIsolated<Value> {

    private var storage: Value

    /// Wraps `value`, taking exclusive ownership of it inside the actor.
    public init(_ value: Value) {
        self.storage = value
    }

    /// The current value.
    ///
    /// Each access hops to the actor, so a sequence of `await box.value`
    /// reads interleaved with writes from other tasks always observes a
    /// consistent (never partially-mutated) value — though the value may
    /// change between two separate awaits.
    public var value: Value {
        storage
    }

    /// Replaces the wrapped value outright.
    public func setValue(_ newValue: Value) {
        storage = newValue
    }

    /// Mutates the wrapped value in place and returns a result computed
    /// from the *new* value, in a single atomic hop to the actor.
    ///
    /// - Parameter mutation: A closure that mutates the value via `inout`.
    /// - Returns: Whatever `mutation` returns.
    @discardableResult
    public func update<Result>(
        _ mutation: (inout Value) throws -> Result
    ) rethrows -> Result {
        try mutation(&storage)
    }

    /// Runs `body` with direct (synchronous) access to the wrapped value,
    /// for reads, writes, or both, as a single atomic operation.
    ///
    /// Useful when an operation needs to read the current value, decide
    /// something, and conditionally write a new one without another task
    /// interleaving in between — something two separate `await` calls to
    /// ``value`` and ``setValue(_:)`` cannot guarantee.
    ///
    /// ```swift
    /// let seen = ActorIsolated<Set<String>>([])
    ///
    /// // Atomic "insert if new" — safe even if called concurrently with
    /// // the same id from many tasks.
    /// let isFirstSighting = await seen.withValue { ids -> Bool in
    ///     let (inserted, _) = ids.insert(eventID)
    ///     return inserted
    /// }
    /// ```
    @discardableResult
    public func withValue<Result>(
        _ body: (inout Value) throws -> Result
    ) rethrows -> Result {
        try body(&storage)
    }
}

// MARK: - Convenience for Equatable values

extension ActorIsolated where Value: Equatable {

    /// Sets the wrapped value to `newValue` only if it currently equals
    /// `expected`, returning whether the swap happened.
    ///
    /// A classic compare-and-swap, useful for guarding one-shot state
    /// transitions (e.g. "only the first task to observe `.idle` should
    /// kick off work") without a separate locking type.
    @discardableResult
    public func compareAndSet(expected: Value, newValue: Value) -> Bool {
        guard storage == expected else { return false }
        storage = newValue
        return true
    }
}

// MARK: - Convenience for numeric values

extension ActorIsolated where Value: AdditiveArithmetic {

    /// Adds `delta` to the wrapped value and returns the new total.
    ///
    /// A shorthand for the common counter/accumulator case:
    /// `await counter.add(1)` instead of `await counter.update { $0 += 1 }`.
    @discardableResult
    public func add(_ delta: Value) -> Value {
        storage += delta
        return storage
    }
}
