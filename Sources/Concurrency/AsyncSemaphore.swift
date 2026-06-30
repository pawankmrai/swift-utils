//
//  AsyncSemaphore.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-06-30.
//

import Foundation

// MARK: - AsyncSemaphore

/// A counting semaphore for `async`/`await` code that *suspends* tasks instead
/// of blocking threads.
///
/// `DispatchSemaphore.wait()` parks the calling thread, which is dangerous in
/// Swift Concurrency: the cooperative thread pool is small, and a blocked
/// thread can deadlock unrelated tasks. `AsyncSemaphore` instead suspends the
/// awaiting task and frees the thread to do other work, resuming the task only
/// once a permit becomes available.
///
/// Waiters are served in **FIFO order**, and the cancellable acquire path
/// cooperates with structured concurrency — cancelling a task that is waiting
/// on a permit throws `CancellationError` and removes it from the queue.
///
/// ```swift
/// // Limit image decoding to 3 concurrent operations.
/// let gate = AsyncSemaphore(value: 3)
///
/// await withTaskGroup(of: UIImage?.self) { group in
///     for url in urls {
///         group.addTask {
///             await gate.withPermit { try? await decodeImage(at: url) }
///         }
///     }
/// }
/// ```
public final class AsyncSemaphore: @unchecked Sendable {

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var permits: Int
    private var waiters: [Waiter] = []
    /// IDs cancelled *before* their continuation was enqueued (closes the race
    /// between `onCancel` firing and the waiter being registered).
    private var cancelledIDs: Set<UUID> = []

    /// Creates a semaphore with the given number of available permits.
    ///
    /// - Parameter value: The initial (and maximum baseline) permit count.
    ///   Must be `>= 0`.
    public init(value: Int) {
        precondition(value >= 0, "AsyncSemaphore value must be >= 0")
        self.permits = value
    }

    /// The number of permits currently available. Intended for debugging and
    /// tests; treat it as a snapshot that may be stale the moment it returns.
    public var availablePermits: Int {
        lock.lock()
        defer { lock.unlock() }
        return permits
    }

    // MARK: Acquire

    /// Waits for a permit, suspending the current task until one is available.
    ///
    /// This variant ignores cancellation. Use ``waitUnlessCancelled()`` if the
    /// wait should abort when the surrounding task is cancelled.
    public func wait() async {
        // The non-cancellable path never resumes with an error.
        try? await acquire(cancellable: false)
    }

    /// Waits for a permit, throwing `CancellationError` if the current task is
    /// cancelled before (or while) waiting.
    ///
    /// - Throws: `CancellationError` if cancelled while suspended.
    public func waitUnlessCancelled() async throws {
        try await acquire(cancellable: true)
    }

    private func acquire(cancellable: Bool) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()

                if cancellable, cancelledIDs.remove(id) != nil {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if cancellable, Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if permits > 0 {
                    permits -= 1
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters.append(Waiter(id: id, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            guard cancellable else { return }
            lock.lock()
            if let index = waiters.firstIndex(where: { $0.id == id }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                // Continuation not enqueued yet — remember the cancellation.
                cancelledIDs.insert(id)
                lock.unlock()
            }
        }
    }

    // MARK: Release

    /// Signals the semaphore, releasing one permit.
    ///
    /// If a task is waiting, the longest-waiting one is resumed; otherwise the
    /// available permit count is incremented.
    public func signal() {
        lock.lock()
        if waiters.isEmpty {
            permits += 1
            lock.unlock()
            return
        }
        let waiter = waiters.removeFirst()
        lock.unlock()
        waiter.continuation.resume()
    }

    // MARK: Scoped helper

    /// Acquires a permit, runs `operation`, and guarantees the permit is
    /// released even if `operation` throws.
    ///
    /// - Parameter operation: The work to perform while holding a permit.
    /// - Returns: The value produced by `operation`.
    /// - Throws: Any error thrown by `operation`.
    public func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await wait()
        defer { signal() }
        return try await operation()
    }
}
