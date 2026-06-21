//
//  TaskBag.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-06-21.
//

import Foundation

// MARK: - TaskBag

/// A thread-safe container that collects `Task` handles so they can be
/// cancelled together — the structured-concurrency equivalent of Combine's
/// `Set<AnyCancellable>`.
///
/// Store any in-flight `Task` in a `TaskBag` owned by a view controller,
/// view model, or coordinator. When the owner is deallocated, every task
/// still in the bag is automatically cancelled. Tasks that finish on their
/// own are removed from the bag as soon as they complete, so a long-lived
/// bag never accumulates stale entries.
///
/// ```swift
/// final class SearchViewModel {
///     private let tasks = TaskBag()
///
///     func search(_ query: String) {
///         Task {
///             let results = try await api.search(query)
///             await MainActor.run { self.results = results }
///         }.store(in: tasks)
///     }
///
///     // When `SearchViewModel` deinits, any in-flight search is cancelled.
/// }
/// ```
public final class TaskBag: @unchecked Sendable {

    // MARK: - Properties

    private var tasks: [UUID: AnyCancellableTask] = [:]
    private let lock = NSLock()

    /// The number of tasks currently tracked by the bag.
    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return tasks.count
    }

    /// Whether the bag currently holds no tasks.
    public var isEmpty: Bool { count == 0 }

    // MARK: - Initialization

    /// Creates an empty task bag.
    public init() {}

    // MARK: - Public API

    /// Adds a non-throwing task to the bag.
    ///
    /// The task is automatically removed from the bag once it finishes,
    /// whether normally or via cancellation.
    /// - Parameter task: The task to track.
    public func add<Success>(_ task: Task<Success, Never>) {
        let id = UUID()
        insert(task, id: id)
        Task { [weak self] in
            _ = await task.value
            self?.remove(id)
        }
    }

    /// Adds a throwing task to the bag.
    ///
    /// The task is automatically removed from the bag once it finishes,
    /// whether it succeeds, throws, or is cancelled.
    /// - Parameter task: The task to track.
    public func add<Success>(_ task: Task<Success, Error>) {
        let id = UUID()
        insert(task, id: id)
        Task { [weak self] in
            _ = await task.result
            self?.remove(id)
        }
    }

    /// Cancels every task currently in the bag and empties it.
    ///
    /// Safe to call multiple times, and called automatically on `deinit`.
    public func cancelAll() {
        lock.lock()
        let current = tasks
        tasks.removeAll()
        lock.unlock()

        for (_, task) in current {
            task.cancel()
        }
    }

    // MARK: - Private

    private func insert(_ task: AnyCancellableTask, id: UUID) {
        lock.lock()
        tasks[id] = task
        lock.unlock()
    }

    private func remove(_ id: UUID) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }

    deinit {
        cancelAll()
    }
}

// MARK: - AnyCancellableTask

/// Type-erases `Task<Success, Failure>` down to its `cancel()` capability so
/// tasks with differing generic parameters can share a single collection.
private protocol AnyCancellableTask {
    func cancel()
}

extension Task: AnyCancellableTask {}

// MARK: - Task + store(in:)

extension Task where Failure == Never {

    /// Stores this task in the given bag, mirroring Combine's
    /// `.store(in: &cancellables)`.
    /// - Parameter bag: The bag that should retain and eventually cancel this task.
    /// - Returns: The same task, for further chaining if needed.
    @discardableResult
    public func store(in bag: TaskBag) -> Task<Success, Failure> {
        bag.add(self)
        return self
    }
}

extension Task where Failure == Error {

    /// Stores this task in the given bag, mirroring Combine's
    /// `.store(in: &cancellables)`.
    /// - Parameter bag: The bag that should retain and eventually cancel this task.
    /// - Returns: The same task, for further chaining if needed.
    @discardableResult
    public func store(in bag: TaskBag) -> Task<Success, Failure> {
        bag.add(self)
        return self
    }
}
