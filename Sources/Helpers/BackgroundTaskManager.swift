import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

// MARK: - BackgroundTaskManager

/// A thread-safe wrapper around `BGTaskScheduler` that removes the
/// boilerplate of registering, scheduling, and handling iOS background
/// tasks (app refresh and processing tasks).
///
/// Apple's raw `BGTaskScheduler` API requires registering handlers before
/// `application(_:didFinishLaunchingWithOptions:)` returns, manually calling
/// `setTaskCompleted(success:)`, wiring an `expirationHandler`, and
/// re-scheduling the next run yourself — all easy to get wrong.
///
/// `BackgroundTaskManager` centralizes that bookkeeping behind a small,
/// closure-based API and a lock-protected in-memory log of recent runs,
/// so you can inspect what happened without standing up your own
/// diagnostics.
///
/// ## Quick start
///
/// Register identifiers in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`,
/// then in `application(_:didFinishLaunchingWithOptions:)`:
///
/// ```swift
/// BackgroundTaskManager.shared.register(
///     identifier: "com.myapp.refresh",
///     kind: .appRefresh
/// ) { context in
///     await SyncService.shared.syncLatestData()
/// }
/// ```
///
/// Then schedule the next run, typically when entering background:
///
/// ```swift
/// BackgroundTaskManager.shared.scheduleAppRefresh(
///     identifier: "com.myapp.refresh",
///     earliestBeginDate: Date().addingTimeInterval(15 * 60)
/// )
/// ```
///
/// - Note: Background tasks only run on physical devices under conditions
///   decided by the system (charging state, network availability, usage
///   patterns). Use Xcode's `e -l objc -- -[BGTaskScheduler ...]` debugger
///   command, documented by Apple, to force a run while testing.
public final class BackgroundTaskManager: @unchecked Sendable {

    /// The kind of background task being registered/scheduled.
    public enum TaskKind {
        /// A short, periodic refresh task (`BGAppRefreshTaskRequest`).
        case appRefresh
        /// A longer-running maintenance task, e.g. database cleanup or
        /// pre-fetching (`BGProcessingTaskRequest`).
        case processing(requiresNetwork: Bool, requiresExternalPower: Bool)
    }

    /// The outcome of a single background task execution, kept for
    /// diagnostics.
    public struct RunRecord: Sendable, Equatable {
        public let identifier: String
        public let startedAt: Date
        public let finishedAt: Date
        public let succeeded: Bool
        public let expired: Bool

        public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    }

    /// Errors thrown by scheduling calls.
    public enum SchedulingError: LocalizedError {
        case backgroundTasksUnavailable
        case underlying(Error)

        public var errorDescription: String? {
            switch self {
            case .backgroundTasksUnavailable:
                return "BackgroundTasks framework is unavailable on this platform."
            case .underlying(let error):
                return "Failed to submit background task request: \(error.localizedDescription)"
            }
        }
    }

    /// The shared, app-wide manager. Background task identifiers must be
    /// globally unique per app, so a singleton keeps registration in one
    /// place.
    public static let shared = BackgroundTaskManager()

    private let recordsLock = NSLock()
    private var _records: [RunRecord] = []
    private let maxRecords: Int

    /// Creates a manager. Prefer ``shared`` unless you specifically need an
    /// isolated instance (e.g. in tests).
    /// - Parameter maxRecords: How many recent run records to retain in memory.
    public init(maxRecords: Int = 20) {
        self.maxRecords = maxRecords
    }

    /// Registers a handler for a background task identifier. Must be called
    /// before the app finishes launching (typically from
    /// `application(_:didFinishLaunchingWithOptions:)`), and the identifier
    /// must be listed in `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`.
    ///
    /// - Parameters:
    ///   - identifier: The task identifier, matching `Info.plist`.
    ///   - kind: Whether this is an app refresh or processing task.
    ///   - handler: An async closure performing the work. Its return value
    ///     indicates success; throwing or being cancelled counts as failure.
    #if canImport(BackgroundTasks)
    @discardableResult
    public func register(
        identifier: String,
        kind: TaskKind,
        handler: @escaping (BGTask) async -> Bool
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let self else { task.setTaskCompleted(success: false); return }
            self.run(task: task, identifier: identifier, handler: handler)
        }
    }

    private func run(task: BGTask, identifier: String, handler: @escaping (BGTask) async -> Bool) {
        let startedAt = Date()
        let workItem = Task {
            let success = await handler(task)
            self.record(identifier: identifier, startedAt: startedAt, succeeded: success, expired: false)
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = { [weak self] in
            workItem.cancel()
            self?.record(identifier: identifier, startedAt: startedAt, succeeded: false, expired: true)
        }
    }

    /// Submits an app refresh request for the given identifier.
    ///
    /// - Parameters:
    ///   - identifier: A previously-registered task identifier.
    ///   - earliestBeginDate: The earliest the system should consider running
    ///     the task. The system may run it later depending on usage patterns.
    public func scheduleAppRefresh(
        identifier: String,
        earliestBeginDate: Date? = nil
    ) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            throw SchedulingError.underlying(error)
        }
    }

    /// Submits a processing task request for the given identifier.
    ///
    /// - Parameters:
    ///   - identifier: A previously-registered task identifier.
    ///   - earliestBeginDate: The earliest the system should consider running the task.
    ///   - requiresNetwork: Whether network connectivity is required.
    ///   - requiresExternalPower: Whether the device must be plugged in.
    public func scheduleProcessing(
        identifier: String,
        earliestBeginDate: Date? = nil,
        requiresNetwork: Bool = false,
        requiresExternalPower: Bool = false
    ) throws {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = requiresNetwork
        request.requiresExternalPower = requiresExternalPower
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            throw SchedulingError.underlying(error)
        }
    }

    /// Cancels a previously-scheduled task request, if any is pending.
    public func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    /// Cancels every pending background task request submitted by this app.
    public func cancelAll() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }
    #endif

    /// The most recent run records, newest first, up to `maxRecords`.
    public var recentRuns: [RunRecord] {
        recordsLock.lock()
        defer { recordsLock.unlock() }
        return _records
    }

    /// Returns the most recent run for a given identifier, if any.
    public func lastRun(for identifier: String) -> RunRecord? {
        recentRuns.first { $0.identifier == identifier }
    }

    /// Records a run outcome. Internal (rather than private) so it can be
    /// exercised directly from unit tests via `@testable import`, since
    /// constructing a real `BGTask` outside the system is not possible.
    func record(identifier: String, startedAt: Date, succeeded: Bool, expired: Bool) {
        let entry = RunRecord(
            identifier: identifier,
            startedAt: startedAt,
            finishedAt: Date(),
            succeeded: succeeded,
            expired: expired
        )
        recordsLock.lock()
        _records.insert(entry, at: 0)
        if _records.count > maxRecords {
            _records.removeLast(_records.count - maxRecords)
        }
        recordsLock.unlock()
    }
}
