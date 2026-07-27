//
//  AsyncBatcher.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-27.
//

import Foundation

// MARK: - AsyncBatcherError

/// Errors produced by ``AsyncBatcher``.
public enum AsyncBatcherError: Error, Equatable, Sendable {
    /// The batcher was torn down (via ``AsyncBatcher/cancelAll()`` or
    /// deinitialization) while this item's request was still pending.
    case cancelled
    /// The batch handler returned a different number of results than the
    /// number of items it was given, so results could not be matched back
    /// to their callers.
    case resultCountMismatch(expected: Int, actual: Int)
}

// MARK: - AsyncBatcher

/// Collects individual async requests submitted from anywhere in the app and
/// executes them together as a single batch — either once `maxBatchSize`
/// items have accumulated, or after `maxDelay` has elapsed since the first
/// item in the batch arrived, whichever comes first.
///
/// This is the inverse of a deduplicating coordinator like `SingleFlight`:
/// instead of collapsing *identical* calls into one, `AsyncBatcher` coalesces
/// *distinct* calls that are cheaper to perform together than one at a time —
/// think "mark these 12 notifications read in one request" instead of 12
/// separate round trips, or batching analytics events, Core Data saves, or
/// GraphQL field resolvers.
///
/// ```swift
/// let batcher = AsyncBatcher<String, UserProfile>(maxBatchSize: 20, maxDelay: 0.05) { ids in
///     try await api.fetchProfiles(ids: ids) // one network call for the whole batch
/// }
///
/// // Called from many cells as they scroll into view; every call that lands
/// // within the same 50ms window (or the first 20 of them) becomes one
/// // request instead of one-per-cell.
/// let profile = try await batcher.add(userID)
/// ```
///
/// The batch `handler` must return exactly one result per item, **in the
/// same order** the items were passed in. If it can't produce a result for a
/// particular item, throw from the handler instead — every caller in that
/// batch receives the thrown error.
public actor AsyncBatcher<Item: Sendable, Output: Sendable> {

    /// A single queued request awaiting the next flush.
    private struct PendingRequest {
        let item: Item
        let continuation: CheckedContinuation<Output, Error>
    }

    private let maxBatchSize: Int
    private let maxDelay: TimeInterval
    private let handler: @Sendable ([Item]) async throws -> [Output]

    private var pending: [PendingRequest] = []
    private var flushTask: Task<Void, Never>?

    /// Creates a batcher.
    /// - Parameters:
    ///   - maxBatchSize: The batch is flushed immediately once it reaches
    ///     this many items. Defaults to `Int.max`, meaning size alone never
    ///     triggers a flush — only `maxDelay` does.
    ///   - maxDelay: How long to wait, after the first item of a new batch
    ///     arrives, before flushing regardless of size. Measured in seconds.
    ///   - handler: Executes a full batch of items and returns one result
    ///     per item, in the same order the items were given.
    public init(
        maxBatchSize: Int = .max,
        maxDelay: TimeInterval,
        handler: @escaping @Sendable ([Item]) async throws -> [Output]
    ) {
        precondition(maxBatchSize > 0, "maxBatchSize must be positive")
        precondition(maxDelay > 0, "maxDelay must be positive")
        self.maxBatchSize = maxBatchSize
        self.maxDelay = maxDelay
        self.handler = handler
    }

    deinit {
        flushTask?.cancel()
        for request in pending {
            request.continuation.resume(throwing: AsyncBatcherError.cancelled)
        }
    }

    // MARK: Adding work

    /// Queues `item` for the next batch and suspends until that batch has
    /// been executed, returning this item's corresponding result.
    ///
    /// - Parameter item: The unit of work to add to the current (or next)
    ///   batch.
    /// - Returns: The result produced by the batch `handler` for this item.
    /// - Throws: Whatever the batch `handler` throws, an
    ///   ``AsyncBatcherError/resultCountMismatch(expected:actual:)`` if
    ///   results couldn't be matched to items, or
    ///   ``AsyncBatcherError/cancelled`` if the batcher was torn down first.
    public func add(_ item: Item) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(PendingRequest(item: item, continuation: continuation))

            if pending.count >= maxBatchSize {
                flushTask?.cancel()
                flushTask = nil
                let batch = drainPending()
                Task { await self.execute(batch) }
            } else if flushTask == nil {
                scheduleFlush()
            }
        }
    }

    // MARK: Introspection

    /// The number of items currently queued, awaiting the next flush.
    public var pendingCount: Int {
        pending.count
    }

    // MARK: Manual control

    /// Immediately executes the current batch (if any), without waiting for
    /// `maxDelay` or `maxBatchSize` to be reached. Useful when you know no
    /// more items are coming — e.g. a screen is about to disappear, or the
    /// app is about to be backgrounded.
    public func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        let batch = drainPending()
        guard !batch.isEmpty else { return }
        await execute(batch)
    }

    /// Rejects every pending request with ``AsyncBatcherError/cancelled``
    /// and discards them without ever invoking the handler.
    public func cancelAll() {
        flushTask?.cancel()
        flushTask = nil
        for request in pending {
            request.continuation.resume(throwing: AsyncBatcherError.cancelled)
        }
        pending.removeAll()
    }

    // MARK: Private

    private func drainPending() -> [PendingRequest] {
        defer { pending.removeAll() }
        return pending
    }

    private func scheduleFlush() {
        flushTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(maxDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.timerFired()
        }
    }

    private func timerFired() async {
        flushTask = nil
        let batch = drainPending()
        guard !batch.isEmpty else { return }
        await execute(batch)
    }

    private func execute(_ batch: [PendingRequest]) async {
        do {
            let results = try await handler(batch.map(\.item))
            guard results.count == batch.count else {
                let error = AsyncBatcherError.resultCountMismatch(expected: batch.count, actual: results.count)
                for request in batch {
                    request.continuation.resume(throwing: error)
                }
                return
            }
            for (request, result) in zip(batch, results) {
                request.continuation.resume(returning: result)
            }
        } catch {
            for request in batch {
                request.continuation.resume(throwing: error)
            }
        }
    }
}
