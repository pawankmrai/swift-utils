//
//  ConcurrentMap.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-06-25.
//

import Foundation

// MARK: - Concurrent collection processing

/// `TaskGroup`-backed concurrent transforms for sequences.
///
/// These extensions are the parallel counterparts to `map`, `forEach`, and
/// `compactMap`: instead of awaiting each async transform one at a time,
/// every element's work is fanned out into a `TaskGroup`, optionally capped
/// at a maximum concurrency, and results are reassembled in the original
/// input order.
///
/// ```swift
/// let avatars = try await userIDs.concurrentMap(maxConcurrency: 6) { id in
///     try await imageService.fetchAvatar(for: id)
/// }
/// ```
public extension Sequence where Element: Sendable {

    /// Transforms every element concurrently, preserving input order in the
    /// returned array.
    ///
    /// All elements start their transform immediately unless `maxConcurrency`
    /// is supplied, in which case at most that many transforms run at once —
    /// the next element starts as soon as a slot frees up.
    ///
    /// If any transform throws, the first error encountered is rethrown and
    /// all other in-flight work is cancelled (matching `TaskGroup` semantics).
    ///
    /// - Parameters:
    ///   - maxConcurrency: Maximum number of transforms running at once.
    ///     `nil` (the default) means unbounded. Must be `nil` or ≥ 1.
    ///   - transform: An async, throwing closure producing the mapped value.
    /// - Returns: The transformed values, in the same order as the input.
    /// - Throws: The first error thrown by any `transform` invocation.
    func concurrentMap<T: Sendable>(
        maxConcurrency: Int? = nil,
        _ transform: @Sendable @escaping (Element) async throws -> T
    ) async throws -> [T] {
        let items = Array(self)
        guard !items.isEmpty else { return [] }

        let limit = maxConcurrency ?? items.count
        precondition(limit > 0, "maxConcurrency must be at least 1")

        return try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var results = [T?](repeating: nil, count: items.count)
            var nextIndex = 0

            func scheduleNext() {
                guard nextIndex < items.count else { return }
                let index = nextIndex
                let element = items[index]
                nextIndex += 1
                group.addTask {
                    let value = try await transform(element)
                    return (index, value)
                }
            }

            for _ in 0..<min(limit, items.count) {
                scheduleNext()
            }

            while let (index, value) = try await group.next() {
                results[index] = value
                scheduleNext()
            }

            return results.map { $0! }
        }
    }

    /// Performs an async, throwing operation against every element
    /// concurrently, discarding results.
    ///
    /// - Parameters:
    ///   - maxConcurrency: Maximum number of operations running at once.
    ///     `nil` means unbounded.
    ///   - operation: The async, throwing work to perform per element.
    /// - Throws: The first error thrown by any `operation` invocation.
    func concurrentForEach(
        maxConcurrency: Int? = nil,
        _ operation: @Sendable @escaping (Element) async throws -> Void
    ) async throws {
        _ = try await concurrentMap(maxConcurrency: maxConcurrency) { element in
            try await operation(element)
        }
    }

    /// Transforms every element concurrently and drops `nil` results — the
    /// async, parallel counterpart to `Sequence.compactMap`.
    ///
    /// - Parameters:
    ///   - maxConcurrency: Maximum number of transforms running at once.
    ///     `nil` means unbounded.
    ///   - transform: An async, throwing closure producing an optional value.
    /// - Returns: The non-`nil` transformed values, in input order.
    /// - Throws: The first error thrown by any `transform` invocation.
    func concurrentCompactMap<T: Sendable>(
        maxConcurrency: Int? = nil,
        _ transform: @Sendable @escaping (Element) async throws -> T?
    ) async throws -> [T] {
        try await concurrentMap(maxConcurrency: maxConcurrency, transform).compactMap { $0 }
    }
}

// MARK: - First-to-finish racing

/// Races multiple async operations against each other and surfaces whichever
/// finishes first — successfully.
///
/// Useful for hitting redundant endpoints, racing a primary data source
/// against a cache warm-up, or any "first one wins" workflow.
public enum ConcurrentRace {

    /// Runs all operations concurrently and returns the value produced by
    /// whichever finishes successfully first. The remaining operations are
    /// cancelled as soon as a winner is found.
    ///
    /// If every operation throws, the error from the last operation to fail
    /// is rethrown.
    ///
    /// ```swift
    /// let config = try await ConcurrentRace.firstSuccess([
    ///     { try await api.fetchConfig(host: .primary) },
    ///     { try await api.fetchConfig(host: .backup) },
    /// ])
    /// ```
    ///
    /// - Parameter operations: The async, throwing operations to race.
    /// - Returns: The first successfully produced value.
    /// - Throws: `ConcurrentRaceError.noOperations` if `operations` is empty,
    ///   otherwise the last encountered error if every operation fails.
    public static func firstSuccess<T: Sendable>(
        _ operations: [@Sendable () async throws -> T]
    ) async throws -> T {
        guard !operations.isEmpty else { throw ConcurrentRaceError.noOperations }

        return try await withThrowingTaskGroup(of: T.self) { group in
            for operation in operations {
                group.addTask { try await operation() }
            }

            var lastError: Error?
            while !group.isEmpty {
                do {
                    if let value = try await group.next() {
                        group.cancelAll()
                        return value
                    }
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? ConcurrentRaceError.noOperations
        }
    }
}

/// Errors thrown by `ConcurrentRace`.
public enum ConcurrentRaceError: Error, Sendable, Equatable {
    /// `firstSuccess` was called with an empty operations array.
    case noOperations
}
