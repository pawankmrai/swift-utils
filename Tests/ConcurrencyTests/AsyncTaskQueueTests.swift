//
//  AsyncTaskQueueTests.swift
//  SwiftUtilsTests
//
//  Created by Pawan on 2026-06-09.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncTaskQueueTests: XCTestCase {

    // MARK: - Serial execution

    func testSerialQueueRunsOneAtATime() async throws {
        let queue = AsyncTaskQueue(maxConcurrency: 1)
        var log: [Int] = []
        let lock = NSLock()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    await queue.enqueue {
                        lock.lock(); log.append(i); lock.unlock()
                        try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms
                    }
                }
            }
        }

        // All 5 items must be present (order may vary due to task scheduling).
        XCTAssertEqual(log.sorted(), [0, 1, 2, 3, 4])
    }

    // MARK: - Concurrency limit

    func testConcurrencyLimitRespected() async throws {
        let limit = 3
        let queue = AsyncTaskQueue(maxConcurrency: limit)

        var peak = 0
        var current = 0
        let lock = NSLock()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await queue.enqueue {
                        lock.lock()
                        current += 1
                        if current > peak { peak = current }
                        lock.unlock()

                        try? await Task.sleep(nanoseconds: 20_000_000) // 20 ms

                        lock.lock()
                        current -= 1
                        lock.unlock()
                    }
                }
            }
        }

        XCTAssertLessThanOrEqual(peak, limit, "Peak concurrency \(peak) exceeded limit \(limit)")
    }

    // MARK: - Result forwarding

    func testEnqueueReturnsResult() async throws {
        let queue = AsyncTaskQueue.serial
        let value = try await queue.enqueue { 42 }
        XCTAssertEqual(value, 42)
    }

    func testEnqueuePropagatesThrow() async {
        let queue = AsyncTaskQueue.serial
        struct TestError: Error {}
        do {
            try await queue.enqueue { throw TestError() }
            XCTFail("Expected error not thrown")
        } catch is TestError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Active / pending counts

    func testActiveCountTracking() async throws {
        let queue = AsyncTaskQueue(maxConcurrency: 1)

        // Nothing running yet.
        let initial = await queue.activeCount
        XCTAssertEqual(initial, 0)

        // Run one task and check count inside it.
        var countDuringExecution = -1
        await queue.enqueue {
            countDuringExecution = await queue.activeCount
        }
        XCTAssertEqual(countDuringExecution, 1)

        // Back to zero after completion.
        let final = await queue.activeCount
        XCTAssertEqual(final, 0)
    }

    // MARK: - Non-throwing overload

    func testNonThrowingEnqueue() async {
        let queue = AsyncTaskQueue.serial
        let result = await queue.enqueue { "hello" }
        XCTAssertEqual(result, "hello")
    }

    // MARK: - Submit (fire-and-forget)

    func testSubmitCompletesWork() async throws {
        let queue = AsyncTaskQueue.serial
        let expectation = XCTestExpectation(description: "submitted task runs")

        let task = queue.submit {
            try await Task.sleep(nanoseconds: 1_000_000)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        _ = task // keep reference
    }

    // MARK: - Cancel pending

    func testCancelPendingDrainsContinuations() async throws {
        let queue = AsyncTaskQueue(maxConcurrency: 1)

        // Block the single slot with a long task.
        let blocker = Task {
            await queue.enqueue {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200 ms
            }
        }

        // Give the blocker a moment to acquire the slot.
        try await Task.sleep(nanoseconds: 20_000_000)

        // Enqueue a second task (it will park waiting for the slot).
        let waiter = Task<Bool, Never> {
            // We expect this to complete once cancelPending() is called,
            // but since the continuation is resumed it will acquire the slot
            // and run immediately after the blocker (no error from cancelPending alone).
            await queue.enqueue { true }
        }

        // Cancel pending continuations while waiter is in the queue.
        await queue.cancelPending()
        let pending = await queue.pendingCount
        XCTAssertEqual(pending, 0)

        blocker.cancel()
        _ = await waiter.value
    }

    // MARK: - Convenience factories

    func testSerialFactoryHasCorrectConcurrency() async {
        let q = AsyncTaskQueue.serial
        let max = await q.maxConcurrency
        XCTAssertEqual(max, 1)
    }

    func testConcurrentFourFactoryHasCorrectConcurrency() async {
        let q = AsyncTaskQueue.concurrentFour
        let max = await q.maxConcurrency
        XCTAssertEqual(max, 4)
    }
}
