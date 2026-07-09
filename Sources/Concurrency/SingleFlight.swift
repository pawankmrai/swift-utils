//
//  SingleFlight.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-09.
//

import Foundation

// MARK: - SingleFlight

/// Deduplicates concurrent async work sharing the same key, so that no matter
/// how many callers request it at once, the underlying `operation` runs
/// **at most once per key** at any given time.
///
/// This is the classic "single-flight" pattern (see Go's `singleflight`
/// package): if five collection view cells all ask for the same user profile
/// within the same frame, only one network request is made — the other four
/// simply await the result of the request already in flight.
///
/// `SingleFlight` does **not** cache completed results; once a key's
/// operation finishes (successfully or not), the next call for that key
/// starts fresh work. Pair it with a cache (e.g. `ResponseCache`) if you also
/// want to remember results after the in-flight window closes.
///
/// ```swift
/// let flight = SingleFlight<String, UserProfile>()
///
/// // Called from many places at once (cell reuse, prefetch, pull-to-refresh)
/// // — only the first caller actually hits the network.
/// func loadProfile(id: String) async throws -> UserProfile {
///     try await flight.execute(key: id) {
///         try await api.fetchProfile(id: id)
///     }
/// }
/// ```
public actor SingleFlight<Key: Hashable & Sendable, Value: Sendable> {

    /// In-progress work keyed by request key. A key is removed as soon as its
    /// task completes, so it is only ever present while genuinely in flight.
    private var inFlightTasks: [Key: Task<Value, Error>] = [:]

    /// Creates an empty coordinator.
    public init() {}

    // MARK: Execute

    /// Runs `operation` for `key`, or — if a call for the same `key` is
    /// already running — awaits that call's result instead of starting a new
    /// one.
    ///
    /// All callers that arrive while a key is in flight receive the exact
    /// same result (or the exact same error) as the original caller; they
    /// never trigger a second execution of `operation`.
    ///
    /// - Parameters:
    ///   - key: Identifies the unit of work to deduplicate.
    ///   - operation: The async throwing work to perform. Only invoked when
    ///     no call for `key` is currently in flight.
    /// - Returns: The value produced by `operation` (or the in-flight call it
    ///   joined).
    /// - Throws: Whatever `operation` throws (or `CancellationError` if the
    ///   in-flight task was cancelled via ``cancel(_:)``).
    @discardableResult
    public func execute(
        key: Key,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existing = inFlightTasks[key] {
            return try await existing.value
        }

        let task = Task<Value, Error> {
            try await operation()
        }
        inFlightTasks[key] = task

        defer { inFlightTasks[key] = nil }
        return try await task.value
    }

    // MARK: Introspection

    /// Whether work for `key` is currently in flight.
    public func isInFlight(_ key: Key) -> Bool {
        inFlightTasks[key] != nil
    }

    /// The number of distinct keys with work currently in flight.
    public var inFlightCount: Int {
        inFlightTasks.count
    }

    // MARK: Cancellation

    /// Cancels the in-flight task for `key`, if any, and forgets it.
    ///
    /// Every caller awaiting that key — including ones that joined via
    /// ``execute(key:operation:)`` — receives a `CancellationError` (or
    /// whatever error the operation surfaces once it observes cancellation).
    public func cancel(_ key: Key) {
        inFlightTasks[key]?.cancel()
        inFlightTasks[key] = nil
    }

    /// Cancels every in-flight task and clears all tracked keys.
    ///
    /// Useful on sign-out or when tearing down a screen that owns this
    /// coordinator.
    public func cancelAll() {
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
    }
}
