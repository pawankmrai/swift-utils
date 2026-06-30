//
//  AsyncSemaphoreTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-06-30.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncSemaphoreTests: XCTestCase {

    func testInitialPermitsAreAvailable() {
        let semaphore = AsyncSemaphore(value: 2)
        XCTAssertEqual(semaphore.availablePermits, 2)
    }

    func testWaitConsumesPermit() async {
        let semaphore = AsyncSemaphore(value: 1)
        await semaphore.wait()
        XCTAssertEqual(semaphore.availablePermits, 0)
    }

    func testSignalRestoresPermitWhenNoWaiters() async {
        let semaphore = AsyncSemaphore(value: 1)
        await semaphore.wait()
        semaphore.signal()
        XCTAssertEqual(semaphore.availablePermits, 1)
    }

    func testSignalDoesNotExceedByQueueWhenWaiterPresent() async {
        let semaphore = AsyncSemaphore(value: 0)

        // This task blocks until a permit is signalled.
        let task = Task { await semaphore.wait() }
        // Give the task a moment to suspend on the semaphore.
        try? await Task.sleep(nanoseconds: 50_000_000)

        semaphore.signal()       // hands the permit directly to the waiter
        await task.value
        XCTAssertEqual(semaphore.availablePermits, 0)
    }

    func testLimitsConcurrency() async {
        let limit = 3
        let semaphore = AsyncSemaphore(value: limit)
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await semaphore.withPermit {
                        await counter.enter(max: limit)
                        try? await Task.sleep(nanoseconds: 1_000_000)
                        await counter.leave()
                    }
                }
            }
        }

        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, limit)
        XCTAssertEqual(semaphore.availablePermits, limit)
    }

    func testWithPermitReleasesOnThrow() async {
        let semaphore = AsyncSemaphore(value: 1)
        struct Boom: Error {}

        do {
            try await semaphore.withPermit { throw Boom() }
            XCTFail("Expected error to propagate")
        } catch {
            // expected
        }
        XCTAssertEqual(semaphore.availablePermits, 1)
    }

    func testFIFOOrdering() async {
        let semaphore = AsyncSemaphore(value: 0)
        let order = Recorder()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<5 {
                group.addTask {
                    await semaphore.wait()
                    await order.record(index)
                }
                // Stagger enqueue so waiters line up deterministically.
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            // Release them one at a time.
            for _ in 0..<5 {
                semaphore.signal()
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        let recorded = await order.values
        XCTAssertEqual(recorded, [0, 1, 2, 3, 4])
    }

    func testCancellationThrows() async {
        let semaphore = AsyncSemaphore(value: 0)

        let task = Task {
            try await semaphore.waitUnlessCancelled()
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            XCTFail("Expected cancellation to throw")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Helpers

    private actor Counter {
        private(set) var current = 0
        private(set) var peak = 0
        func enter(max: Int) {
            current += 1
            peak = Swift.max(peak, current)
        }
        func leave() { current -= 1 }
    }

    private actor Recorder {
        private(set) var values: [Int] = []
        func record(_ value: Int) { values.append(value) }
    }
}
