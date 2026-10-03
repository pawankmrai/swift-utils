//
//  AsyncBroadcaster.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-10-03.
//

import Foundation

// MARK: - AsyncBroadcaster

/// A multicast channel that fans every sent element out to any number of
/// independent `AsyncStream` subscribers.
///
/// A plain `AsyncStream` is single-consumer: two `for await` loops over the
/// same stream *split* its elements between them. `AsyncBroadcaster` gives each
/// subscriber its own stream, so every subscriber sees every element — the
/// async/await equivalent of a Combine `PassthroughSubject` (or a
/// `CurrentValueSubject` when `replay` is `1`).
///
/// - Elements can be sent synchronously from any thread or actor.
/// - New subscribers optionally receive the last `replay` elements first.
/// - Subscribers are removed automatically when their iterating task is
///   cancelled or their stream is deallocated.
/// - `finish()` completes every current and future subscriber.
///
/// ```swift
/// let auth = AsyncBroadcaster<AuthState>(replay: 1)
///
/// Task { for await state in auth.stream() { updateUI(for: state) } }
/// Task { for await state in auth.stream() { analytics.track(state) } }
///
/// auth.send(.signedIn(user))   // both tasks receive it
/// ```
public final class AsyncBroadcaster<Element: Sendable>: @unchecked Sendable {

    /// Buffering policy applied to each subscriber's stream.
    public typealias BufferingPolicy = AsyncStream<Element>.Continuation.BufferingPolicy

    private let lock = NSLock()
    private let replayLimit: Int
    private let bufferingPolicy: BufferingPolicy
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var replayBuffer: [Element] = []
    private var finished = false

    /// Creates a broadcaster.
    ///
    /// - Parameters:
    ///   - replay: Number of most recent elements delivered to each new
    ///     subscriber before live elements. `0` (the default) means none;
    ///     `1` gives "current value" semantics.
    ///   - bufferingPolicy: Per-subscriber buffering policy. Use
    ///     `.bufferingNewest(1)` for slow consumers that only care about the
    ///     latest state. Defaults to `.unbounded`.
    public init(replay: Int = 0, bufferingPolicy: BufferingPolicy = .unbounded) {
        precondition(replay >= 0, "replay must be non-negative")
        self.replayLimit = replay
        self.bufferingPolicy = bufferingPolicy
    }

    deinit {
        finish()
    }

    // MARK: Subscribing

    /// Returns a new, independent stream that receives the replay buffer
    /// followed by every element sent from now on.
    ///
    /// If the broadcaster has already finished, the stream yields the replay
    /// buffer and then ends immediately.
    public func stream() -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            lock.lock()
            // Yield replay inside the lock so no concurrently sent element can
            // overtake it.
            replayBuffer.forEach { continuation.yield($0) }
            if finished {
                lock.unlock()
                continuation.finish()
                return
            }
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeSubscriber(id)
            }
        }
    }

    // MARK: Sending

    /// Delivers `element` to every current subscriber and records it in the
    /// replay buffer. Ignored after `finish()`.
    public func send(_ element: Element) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if replayLimit > 0 {
            replayBuffer.append(element)
            if replayBuffer.count > replayLimit {
                replayBuffer.removeFirst(replayBuffer.count - replayLimit)
            }
        }
        // `yield` never re-enters `onTermination`, so it is safe under the lock
        // and keeps element ordering consistent across concurrent senders.
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    /// Completes every subscriber's stream. Subsequent sends are ignored and
    /// subsequent subscribers receive only the replay buffer. Idempotent.
    public func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let toFinish = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        // Finish outside the lock: `finish()` synchronously triggers
        // `onTermination`, which takes the lock.
        toFinish.forEach { $0.finish() }
    }

    // MARK: Inspection

    /// Number of currently active subscribers.
    public var subscriberCount: Int {
        lock.lock(); defer { lock.unlock() }
        return continuations.count
    }

    /// Whether `finish()` has been called.
    public var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    /// The most recently sent element, if `replay > 0` and anything has been sent.
    public var latestValue: Element? {
        lock.lock(); defer { lock.unlock() }
        return replayBuffer.last
    }

    // MARK: Private

    private func removeSubscriber(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}
