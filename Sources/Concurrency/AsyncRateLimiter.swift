//
//  AsyncRateLimiter.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-14.
//

import Foundation

// MARK: - AsyncRateLimiter

/// A token-bucket rate limiter for `async`/`await` code that throttles how
/// *often* an operation may run, rather than how many can run concurrently.
///
/// `AsyncSemaphore` caps concurrent access — it says "no more than N at
/// once." `AsyncRateLimiter` caps frequency — it says "no more than N per
/// second," even if every previous call has already finished. Tokens refill
/// continuously (not in discrete ticks), so short bursts up to `capacity` are
/// allowed immediately and the rate smooths out afterward. This is the shape
/// you want in front of a rate-limited API, an analytics pipe, or any
/// downstream system that enforces its own requests-per-second quota.
///
/// Because `AsyncRateLimiter` is an `actor`, callers are naturally serialized
/// and safe to share across tasks without extra locking.
///
/// ```swift
/// // Never send more than 5 requests/second to this API, but allow a burst
/// // of up to 5 immediately if the bucket is full.
/// let limiter = AsyncRateLimiter(capacity: 5, refillInterval: 1)
///
/// for request in requests {
///     try await limiter.acquire()
///     try await api.send(request)
/// }
/// ```
public actor AsyncRateLimiter {

    private let capacity: Double
    private let refillRatePerSecond: Double
    private var tokens: Double
    private var lastRefill: DispatchTime

    /// The maximum number of tokens the bucket can hold (the burst size).
    public var maxCapacity: Int { Int(capacity) }

    /// Creates a rate limiter that allows `capacity` events immediately (a
    /// burst), then refills at a steady rate of `capacity` events per
    /// `refillInterval` seconds.
    ///
    /// - Parameters:
    ///   - capacity: Maximum burst size / bucket size. Must be `> 0`.
    ///   - refillInterval: Seconds required to refill `capacity` tokens from
    ///     empty. For example, `capacity: 5, refillInterval: 1` allows 5
    ///     events/second sustained, with an initial burst of up to 5.
    public init(capacity: Int, refillInterval: TimeInterval) {
        precondition(capacity > 0, "capacity must be > 0")
        precondition(refillInterval > 0, "refillInterval must be > 0")
        self.capacity = Double(capacity)
        self.refillRatePerSecond = Double(capacity) / refillInterval
        self.tokens = Double(capacity)
        self.lastRefill = .now()
    }

    /// The number of tokens currently available, after applying any refill
    /// owed since the last check. Fractional — a value of `2.4` means two
    /// full acquisitions are available right now.
    public var availableTokens: Double {
        refill()
        return tokens
    }

    // MARK: Acquire

    /// Suspends until a token is available, then consumes one.
    ///
    /// Multiple callers may await concurrently; each is served in turn as
    /// tokens refill. Cancelling the calling task aborts the wait and throws
    /// `CancellationError` without consuming a token.
    ///
    /// - Throws: `CancellationError` if the task is cancelled while waiting.
    public func acquire() async throws {
        while true {
            try Task.checkCancellation()
            refill()
            if tokens >= 1 {
                tokens -= 1
                return
            }
            let deficit = 1 - tokens
            let waitSeconds = deficit / refillRatePerSecond
            try await Task.sleep(nanoseconds: UInt64((waitSeconds * 1_000_000_000).rounded(.up)))
        }
    }

    /// Like ``acquire()``, but swallows cancellation instead of throwing —
    /// useful for call sites that don't want to propagate `try`.
    public func acquireIgnoringCancellation() async {
        try? await acquire()
    }

    /// Attempts to consume a token immediately without suspending.
    ///
    /// - Returns: `true` if a token was available and consumed, `false` if
    ///   the caller should back off (e.g. skip, queue, or surface a
    ///   rate-limit error) instead of waiting.
    @discardableResult
    public func tryAcquire() -> Bool {
        refill()
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    /// Acquires a token, runs `operation`, and returns its result.
    ///
    /// Unlike `AsyncSemaphore.withPermit`, the token is *not* released after
    /// `operation` completes — rate limiting is about pacing over time, so
    /// the slot stays spent until the bucket naturally refills.
    ///
    /// - Parameter operation: The throttled work to perform.
    /// - Returns: The value produced by `operation`.
    /// - Throws: `CancellationError` if cancelled while waiting for a token,
    ///   or any error thrown by `operation`.
    public func withThrottle<T>(_ operation: () async throws -> T) async throws -> T {
        try await acquire()
        return try await operation()
    }

    // MARK: Private

    private func refill() {
        let now = DispatchTime.now()
        let elapsedSeconds = Double(now.uptimeNanoseconds &- lastRefill.uptimeNanoseconds) / 1_000_000_000
        guard elapsedSeconds > 0 else { return }
        lastRefill = now
        tokens = Swift.min(capacity, tokens + elapsedSeconds * refillRatePerSecond)
    }
}
