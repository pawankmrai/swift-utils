//
//  AsyncTimeout.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-06-24.
//

import Foundation

// MARK: - TimeoutError

/// An error thrown when an async operation exceeds its allotted time budget.
public struct TimeoutError: Error, LocalizedError, Equatable {

    /// The time budget, in seconds, that was exceeded.
    public let seconds: TimeInterval

    /// Creates a `TimeoutError` for the given time budget.
    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public var errorDescription: String? {
        "Operation timed out after \(seconds) second(s)."
    }
}

// MARK: - withTimeout (throwing)

/// Runs an async, throwing operation and races it against a timer.
///
/// If `operation` finishes first, its result (or error) is returned/thrown
/// as-is. If the timer elapses first, `operation`'s task is cooperatively
/// cancelled and a `TimeoutError` is thrown instead.
///
/// `operation` is responsible for honouring cancellation (e.g. by calling
/// `Task.checkCancellation()` between steps, or by using cancellable APIs
/// such as `URLSession`) so that timing out actually stops the work.
///
/// ```swift
/// let user = try await withTimeout(seconds: 5) {
///     try await api.fetchUser(id: 42)
/// }
/// ```
///
/// - Parameters:
///   - seconds: The maximum time to wait, in seconds.
///   - operation: The async, throwing work to perform.
/// - Returns: The value produced by `operation`, if it completes in time.
/// - Throws: `TimeoutError` if the time budget is exceeded, or any error
///   thrown by `operation` if it fails first.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    precondition(seconds > 0, "seconds must be greater than 0")

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError(seconds: seconds)
        }

        defer { group.cancelAll() }

        // The first task to finish (operation or timer) determines the
        // outcome; cancelAll() above stops whichever one is still running.
        return try await group.next()!
    }
}

// MARK: - withTimeout (default value on timeout)

/// Runs an async operation, returning a fallback value instead of throwing
/// if it does not complete within the given time budget.
///
/// Useful when a timeout should degrade gracefully rather than propagate
/// an error — e.g. falling back to cached or placeholder data.
///
/// ```swift
/// let profile = await withTimeout(seconds: 2, default: Profile.placeholder) {
///     try await api.fetchProfile()
/// }
/// ```
///
/// - Parameters:
///   - seconds: The maximum time to wait, in seconds.
///   - defaultValue: The value to return if the operation times out or throws.
///   - operation: The async, throwing work to perform.
/// - Returns: The operation's result, or `defaultValue` on timeout/failure.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    default defaultValue: @autoclosure @Sendable () -> T,
    operation: @Sendable @escaping () async throws -> T
) async -> T {
    do {
        return try await withTimeout(seconds: seconds, operation: operation)
    } catch {
        return defaultValue()
    }
}

// MARK: - withTimeout (optional result)

/// Runs an async, throwing operation and returns `nil` if it times out,
/// instead of throwing `TimeoutError`. Errors from `operation` itself are
/// still rethrown so callers can distinguish "timed out" from "failed".
///
/// ```swift
/// if let result = try await withTimeoutOrNil(seconds: 3, operation: fetch) {
///     show(result)
/// } else {
///     showTimedOutState()
/// }
/// ```
///
/// - Parameters:
///   - seconds: The maximum time to wait, in seconds.
///   - operation: The async, throwing work to perform.
/// - Returns: The operation's result, or `nil` if the time budget elapsed.
/// - Throws: Any error thrown by `operation` (but not `TimeoutError`).
public func withTimeoutOrNil<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T? {
    do {
        return try await withTimeout(seconds: seconds, operation: operation)
    } catch is TimeoutError {
        return nil
    } catch {
        throw error
    }
}
