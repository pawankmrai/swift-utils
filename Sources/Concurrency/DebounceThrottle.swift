//
//  DebounceThrottle.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-05-06.
//

import Foundation

// MARK: - Debouncer

/// A thread-safe debouncer that delays execution of a closure until a specified
/// time interval has elapsed since the last invocation.
///
/// Useful for scenarios like search-as-you-type, where you want to wait for the
/// user to stop typing before firing a network request.
///
/// ```swift
/// let debouncer = Debouncer(delay: 0.3)
///
/// textField.addAction(UIAction { _ in
///     debouncer.debounce {
///         viewModel.search(query: textField.text ?? "")
///     }
/// }, for: .editingChanged)
/// ```
public final class Debouncer: @unchecked Sendable {

    // MARK: - Properties

    /// The delay interval in seconds before the debounced action fires.
    public let delay: TimeInterval

    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new debouncer.
    /// - Parameters:
    ///   - delay: The time interval (in seconds) to wait after the last call
    ///            before executing the action. Must be positive.
    ///   - queue: The dispatch queue on which the action will be executed.
    ///            Defaults to the main queue.
    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        precondition(delay > 0, "Delay must be a positive value.")
        self.delay = delay
        self.queue = queue
    }

    // MARK: - Public API

    /// Schedules the given action, cancelling any previously pending action.
    ///
    /// Each call resets the timer. The action will only execute after `delay`
    /// seconds have passed without another call to `debounce`.
    /// - Parameter action: The closure to execute after the delay.
    public func debounce(action: @escaping () -> Void) {
        lock.lock()
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Cancels any pending debounced action.
    public func cancel() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}

// MARK: - Throttler

/// A thread-safe throttler that ensures an action is executed at most once
/// within a specified time interval.
///
/// Supports both leading-edge and trailing-edge execution:
/// - **Leading**: The action fires immediately on the first call, then ignores
///   subsequent calls until the interval elapses.
/// - **Trailing**: The most recent action is saved and fired after the interval
///   elapses.
///
/// ```swift
/// let throttler = Throttler(interval: 0.5, mode: .leadingAndTrailing)
///
/// scrollView.delegate = self
/// func scrollViewDidScroll(_ scrollView: UIScrollView) {
///     throttler.throttle {
///         updateParallaxEffect(offset: scrollView.contentOffset)
///     }
/// }
/// ```
public final class Throttler: @unchecked Sendable {

    // MARK: - Types

    /// Determines when the throttled action fires relative to the interval.
    public enum Mode: Sendable {
        /// Execute on the leading edge only (first call fires immediately).
        case leading
        /// Execute on the trailing edge only (fires after the interval).
        case trailing
        /// Execute on both edges.
        case leadingAndTrailing
    }

    // MARK: - Properties

    /// The minimum time interval between executions.
    public let interval: TimeInterval

    /// The execution mode.
    public let mode: Mode

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var lastExecutionTime: Date?
    private var pendingWorkItem: DispatchWorkItem?
    private var pendingAction: (() -> Void)?

    // MARK: - Initialization

    /// Creates a new throttler.
    /// - Parameters:
    ///   - interval: The minimum time interval (in seconds) between executions.
    ///               Must be positive.
    ///   - mode: The execution mode. Defaults to `.leadingAndTrailing`.
    ///   - queue: The dispatch queue on which the action will be executed.
    ///            Defaults to the main queue.
    public init(
        interval: TimeInterval,
        mode: Mode = .leadingAndTrailing,
        queue: DispatchQueue = .main
    ) {
        precondition(interval > 0, "Interval must be a positive value.")
        self.interval = interval
        self.mode = mode
        self.queue = queue
    }

    // MARK: - Public API

    /// Throttles execution of the given action according to the configured
    /// `mode` and `interval`.
    /// - Parameter action: The closure to execute.
    public func throttle(action: @escaping () -> Void) {
        lock.lock()

        let now = Date()
        let elapsed = lastExecutionTime.map { now.timeIntervalSince($0) }

        // Determine if we are within the throttle window
        let isWithinWindow = elapsed.map { $0 < interval } ?? false

        if !isWithinWindow {
            // Outside the window: fire immediately if leading is enabled
            if mode == .leading || mode == .leadingAndTrailing {
                lastExecutionTime = now
                lock.unlock()
                queue.async { action() }
            } else {
                // Trailing only: schedule for later
                pendingAction = action
                scheduleTrailingExecution()
                lock.unlock()
            }
        } else {
            // Inside the window
            if mode == .trailing || mode == .leadingAndTrailing {
                pendingAction = action
                if pendingWorkItem == nil {
                    scheduleTrailingExecution()
                }
            }
            lock.unlock()
        }
    }

    /// Cancels any pending throttled action.
    public func cancel() {
        lock.lock()
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingAction = nil
        lock.unlock()
    }

    // MARK: - Private

    /// Schedules execution of the most recent pending action at the trailing
    /// edge of the interval. Must be called while `lock` is held.
    private func scheduleTrailingExecution() {
        pendingWorkItem?.cancel()

        let remainingTime: TimeInterval
        if let lastTime = lastExecutionTime {
            remainingTime = max(0, interval - Date().timeIntervalSince(lastTime))
        } else {
            remainingTime = interval
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let action = self.pendingAction
            self.pendingAction = nil
            self.pendingWorkItem = nil
            self.lastExecutionTime = Date()
            self.lock.unlock()
            action?()
        }
        pendingWorkItem = item
        queue.asyncAfter(deadline: .now() + remainingTime, execute: item)
    }
}
