//
//  TaskBagTests.swift
//  SwiftUtilsTests
//
//  Created by Pawan on 2026-06-21.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class TaskBagTests: XCTestCase {

    // MARK: - Basic add / count

    func testAddIncrementsCount() {
        let bag = TaskBag()
        let task = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        }
        bag.add(task)

        XCTAssertEqual(bag.count, 1)
        XCTAssertFalse(bag.isEmpty)

        task.cancel()
    }

    func testEmptyBagReportsIsEmpty() {
        let bag = TaskBag()
        XCTAssertTrue(bag.isEmpty)
        XCTAssertEqual(bag.count, 0)
    }

    // MARK: - Auto-removal on completion

    func testNonThrowingTaskIsRemovedAfterCompletion() async throws {
        let bag = TaskBag()
        let task = Task {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20 ms
        }
        bag.add(task)
        XCTAssertEqual(bag.count, 1)

        _ = await task.value

        // Give the internal watcher a moment to remove the entry.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(bag.isEmpty, "Completed task should be auto-removed from the bag")
    }

    func testThrowingTaskIsRemovedAfterCompletion() async throws {
        let bag = TaskBag()
        struct TestError: Error {}
        let task = Task<Void, Error> {
            throw TestError()
        }
        bag.add(task)

        _ = await task.result

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(bag.isEmpty, "Completed throwing task should be auto-removed from the bag")
    }

    // MARK: - store(in:)

    func testStoreInAddsNonThrowingTask() {
        let bag = TaskBag()
        let task = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let returned = task.store(in: bag)

        XCTAssertEqual(bag.count, 1)
        returned.cancel()
    }

    func testStoreInAddsThrowingTaskAndIsChainable() {
        let bag = TaskBag()
        let task: Task<Int, Error> = Task {
            try await Task.sleep(nanoseconds: 50_000_000)
            return 42
        }
        let returned = task.store(in: bag)

        XCTAssertEqual(bag.count, 1)
        returned.cancel()
    }

    // MARK: - cancelAll

    func testCancelAllCancelsTrackedTasks() async {
        let bag = TaskBag()
        let cancelledExpectation = XCTestExpectation(description: "task observes cancellation")

        let task = Task<Void, Never> {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 500 ms
            } catch {
                // expected: CancellationError surfaces as a thrown error from Task.sleep
                cancelledExpectation.fulfill()
                return
            }
        }
        bag.add(task)

        bag.cancelAll()
        XCTAssertTrue(bag.isEmpty)
        XCTAssertTrue(task.isCancelled)

        await fulfillment(of: [cancelledExpectation], timeout: 2)
    }

    func testCancelAllIsSafeToCallTwice() {
        let bag = TaskBag()
        let task = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        bag.add(task)

        bag.cancelAll()
        bag.cancelAll() // should not crash or throw

        XCTAssertTrue(bag.isEmpty)
    }

    // MARK: - Multiple tasks

    func testMultipleTasksAreAllTracked() {
        let bag = TaskBag()
        let tasks = (0..<5).map { _ in
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        tasks.forEach { $0.store(in: bag) }

        XCTAssertEqual(bag.count, 5)
        bag.cancelAll()
        XCTAssertTrue(bag.isEmpty)
    }

    // MARK: - Deinit cancellation

    func testDeinitCancelsOutstandingTasks() async {
        let task: Task<Void, Never> = makeBagAndTrackLongRunningTask()

        // Give the bag a chance to deallocate and the task a chance to observe cancellation.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(task.isCancelled, "Task should be cancelled once its owning bag deinits")
    }

    /// Creates a `TaskBag` in a nested scope so it deallocates immediately
    /// after this function returns, leaving only the tracked task alive.
    private func makeBagAndTrackLongRunningTask() -> Task<Void, Never> {
        let bag = TaskBag()
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        bag.add(task)
        return task
        // `bag` goes out of scope here and deinits, triggering cancelAll().
    }
}
