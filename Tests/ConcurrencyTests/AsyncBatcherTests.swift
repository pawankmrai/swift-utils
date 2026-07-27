//
//  AsyncBatcherTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-27.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncBatcherTests: XCTestCase {

    func testConcurrentCallsWithinDelayWindowAreBatchedTogether() async throws {
        let invocationCount = Counter()
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 0.05) { items in
            await invocationCount.increment()
            return items.map { $0 * 10 }
        }

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 1...5 {
                group.addTask { try await batcher.add(i) }
            }
            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        XCTAssertEqual(Set(results), Set([10, 20, 30, 40, 50]))
        let count = await invocationCount.value
        XCTAssertEqual(count, 1, "All calls arriving within the delay window should form a single batch")
    }

    func testFlushesImmediatelyWhenMaxBatchSizeReached() async throws {
        let invocationTimes = TimestampLog()
        let batcher = AsyncBatcher<Int, Int>(maxBatchSize: 3, maxDelay: 5.0) { items in
            await invocationTimes.record()
            return items
        }

        let start = Date()
        _ = try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 1...3 {
                group.addTask { try await batcher.add(i) }
            }
            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "Reaching maxBatchSize should flush immediately, not wait for maxDelay")
        let times = await invocationTimes.count
        XCTAssertEqual(times, 1)
    }

    func testSeparateBatchesOverTimeEachInvokeHandlerOnce() async throws {
        let invocationCount = Counter()
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 0.03) { items in
            await invocationCount.increment()
            return items
        }

        _ = try await batcher.add(1)

        // Wait long enough for the first batch to flush and a second, fresh
        // batch to start and flush independently.
        _ = try await batcher.add(2)

        let count = await invocationCount.value
        XCTAssertEqual(count, 2, "Items added after a batch has flushed should form a brand-new batch")
    }

    func testHandlerErrorPropagatesToEveryCallerInTheBatch() async {
        struct Boom: Error, Equatable {}
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 0.05) { _ in
            throw Boom()
        }

        let results = await withTaskGroup(of: Result<Int, Error>.self) { group in
            for i in 1...4 {
                group.addTask {
                    do {
                        return .success(try await batcher.add(i))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<Int, Error>] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, 4)
        for result in results {
            guard case .failure(let error) = result else {
                XCTFail("Expected every caller in the failed batch to receive the error")
                continue
            }
            XCTAssertTrue(error is Boom)
        }
    }

    func testResultCountMismatchIsReportedToAllCallers() async {
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 0.05) { items in
            // Deliberately return fewer results than items.
            Array(items.prefix(1))
        }

        let results = await withTaskGroup(of: Result<Int, Error>.self) { group in
            for i in 1...3 {
                group.addTask {
                    do {
                        return .success(try await batcher.add(i))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<Int, Error>] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for result in results {
            guard case .failure(let error as AsyncBatcherError) = result else {
                XCTFail("Expected a resultCountMismatch error")
                continue
            }
            XCTAssertEqual(error, .resultCountMismatch(expected: 3, actual: 1))
        }
    }

    func testFlushNowExecutesPendingBatchWithoutWaitingForDelay() async throws {
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 10.0) { items in items.map { $0 + 100 } }

        async let result = batcher.add(1)

        // Give the item a moment to register as pending, then force a flush.
        try await Task.sleep(nanoseconds: 20_000_000)
        let countBeforeFlush = await batcher.pendingCount
        XCTAssertEqual(countBeforeFlush, 1)

        await batcher.flushNow()
        let value = try await result
        XCTAssertEqual(value, 101)
    }

    func testCancelAllRejectsPendingCallersWithCancelledError() async {
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 10.0) { items in items }

        let task = Task { try await batcher.add(1) }
        try? await Task.sleep(nanoseconds: 20_000_000)

        await batcher.cancelAll()

        let result = await task.result
        switch result {
        case .success:
            XCTFail("Expected cancellation error")
        case .failure(let error as AsyncBatcherError):
            XCTAssertEqual(error, .cancelled)
        case .failure:
            XCTFail("Expected AsyncBatcherError.cancelled")
        }
        let count = await batcher.pendingCount
        XCTAssertEqual(count, 0)
    }

    func testPendingCountReflectsQueuedItems() async throws {
        let batcher = AsyncBatcher<Int, Int>(maxDelay: 10.0) { items in items }

        async let first = batcher.add(1)
        async let second = batcher.add(2)
        try await Task.sleep(nanoseconds: 20_000_000)

        let count = await batcher.pendingCount
        XCTAssertEqual(count, 2)

        await batcher.flushNow()
        _ = try await (first, second)

        let countAfter = await batcher.pendingCount
        XCTAssertEqual(countAfter, 0)
    }

    // MARK: - Helpers

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private actor TimestampLog {
        private(set) var count = 0
        func record() { count += 1 }
    }
}
