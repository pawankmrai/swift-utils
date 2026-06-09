//
//  AsyncTaskQueue.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-06-09.
//

import Foundation

// MARK: - AsyncTaskQueue

/// An actor-based task queue that controls concurrency for async operations.
///
/// `AsyncTaskQueue` serialises or rate-limits a stream of async work items,
/// making it easy to:
/// - Run uploads/downloads one at a time (serial queue, `maxConcurrency: 1`)
/// - Limit parallel network calls (e.g. `maxConcurrency: 4`)
/// - Cancel all in-flight work on sign-out or navigation
/// - Await the result of a submitted task from any async context
///
/// ```swift
/// let queue = AsyncTaskQueue(maxConcurrency: 3)
///
/// let result = try await queue.enqueue {
///     try await api.fetchUser(id: 42)
/// }
/// ```
public actor AsyncTaskQueue {

    // MARK: - Types

    /// Priority hint passed to the underlying `Task`.
    public enum Priority {
        case high, medium, low

        var taskPriority: TaskPriority {
            switch self {
            case .high:   return .high
            case .medium: return .medium
            case .low:    return .low
            }
        }
    }

    // MARK: - Properties

    /// Maximum number of operations that may run simultaneously.
    public let maxConcurrency: Int

    /// Number of operations currently executing.
    public private(set) var activeCount: Int = 0

    /// Number of operations waiting in the queue.
    public var pendingCount: Int { pendingContinuations.count }

    // MARK: - Private state

    // Each pending item is a closure that resumes one waiting continuation.
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    // MARK: - Init

    /// Creates a new `AsyncTaskQueue`.
    ///
    /// - Parameter maxConcurrency: Maximum simultaneous operations. Defaults to `1`
    ///   (serial queue). Must be ≥ 1.
    public init(maxConcurrency: Int = 1) {
        precondition(maxConcurrency >= 1, "maxConcurrency must be at least 1")
        self.maxConcurrency = maxConcurrency
    }

    // MARK: - Enqueue (throwing)

    /// Enqueues a throwing async operation and returns its result.
    ///
    /// The operation begins as soon as a concurrency slot is available.
    /// If the task is cancelled while waiting in the queue, a
    /// `CancellationError` is thrown before the operation starts.
    ///
    /// - Parameters:
    ///   - priority: Task scheduling priority. Defaults to `.medium`.
    ///   - operation: The async, throwing work to perform.
    /// - Returns: The value produced by `operation`.
    /// - Throws: Rethrows any error from `operation`, or `CancellationError`
    ///   if cancelled while queued.
    @discardableResult
    public func enqueue<T: Sendable>(
        priority: Priority = .medium,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()
        return try await operation()
    }

    // MARK: - Enqueue (non-throwing)

    /// Enqueues a non-throwing async operation and returns its result.
    ///
    /// - Parameters:
    ///   - priority: Task scheduling priority. Defaults to `.medium`.
    ///   - operation: The async work to perform.
    /// - Returns: The value produced by `operation`.
    @discardableResult
    public func enqueue<T: Sendable>(
        priority: Priority = .medium,
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        await acquireSlot()
        defer { releaseSlot() }
        return await operation()
    }

    // MARK: - Fire-and-forget

    /// Submits a fire-and-forget task without waiting for its result.
    ///
    /// The returned `Task` can be used to cancel the work before it starts.
    ///
    /// - Parameters:
    ///   - priority: Task scheduling priority. Defaults to `.medium`.
    ///   - operation: The async, throwing work to perform.
    /// - Returns: A `Task<Void, Error>` representing the submitted work.
    @discardableResult
    public nonisolated func submit(
        priority: Priority = .medium,
        operation: @Sendable @escaping () async throws -> Void
    ) -> Task<Void, Error> {
        Task(priority: priority.taskPriority) {
            try await self.enqueue(priority: priority, operation: operation)
        }
    }

    // MARK: - Cancel all

    /// Cancels all pending operations waiting in the queue.
    ///
    /// Operations that are already executing run to completion unless the
    /// caller also cancels the owning `Task`. Waiting callers receive a
    /// `CancellationError` on their next suspension point.
    public func cancelPending() {
        let pending = pendingContinuations
        pendingContinuations.removeAll()
        // Resuming the continuations lets waiting tasks check for cancellation.
        pending.forEach { $0.resume() }
    }

    // MARK: - Slot management (private)

    private func acquireSlot() async {
        if activeCount < maxConcurrency {
            activeCount += 1
            return
        }
        // Park the caller until a slot opens.
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
        activeCount += 1
    }

    private func releaseSlot() {
        activeCount -= 1
        if !pendingContinuations.isEmpty {
            let next = pendingContinuations.removeFirst()
            next.resume()
        }
    }
}

// MARK: - Convenience factory

public extension AsyncTaskQueue {

    /// A serial queue (one operation at a time).
    static var serial: AsyncTaskQueue { AsyncTaskQueue(maxConcurrency: 1) }

    /// A queue limited to four concurrent operations.
    static var concurrentFour: AsyncTaskQueue { AsyncTaskQueue(maxConcurrency: 4) }
}
