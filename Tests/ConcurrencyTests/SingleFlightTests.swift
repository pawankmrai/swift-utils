//
//  SingleFlightTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-09.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class SingleFlightTests: XCTestCase {

    func testConcurrentCallsForSameKeyRunOperationOnce() async throws {
        let flight = SingleFlight<String, Int>()
        let executions = Counter()

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await flight.execute(key: "profile-1") {
                        await executions.increment()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        return 42
                    }
                }
            }
            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy { $0 == 42 })
        let count = await executions.value
        XCTAssertEqual(count, 1)
    }

    func testDifferentKeysRunIndependently() async throws {
        let flight = SingleFlight<String, Int>()
        let executions = Counter()

        async let a = flight.execute(key: "a") {
            await executions.increment()
            return 1
        }
        async let b = flight.execute(key: "b") {
            await executions.increment()
            return 2
        }

        let (resultA, resultB) = try await (a, b)
        XCTAssertEqual(resultA, 1)
        XCTAssertEqual(resultB, 2)
        let count = await executions.value
        XCTAssertEqual(count, 2)
    }

    func testErrorsPropagateToAllJoinedCallers() async {
        struct Boom: Error, Equatable {}
        let flight = SingleFlight<String, Int>()

        let results = await withTaskGroup(of: Result<Int, Error>.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do {
                        let value = try await flight.execute(key: "boom") {
                            try? await Task.sleep(nanoseconds: 10_000_000)
                            throw Boom()
                        }
                        return .success(value)
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

        XCTAssertEqual(results.count, 5)
        for result in results {
            switch result {
            case .success:
                XCTFail("Expected every caller to observe the failure")
            case .failure(let error):
                XCTAssertTrue(error is Boom)
            }
        }
    }

    func testKeyIsForgottenAfterCompletionSoNextCallRunsAgain() async throws {
        let flight = SingleFlight<String, Int>()
        let executions = Counter()

        let first = try await flight.execute(key: "k") {
            await executions.increment()
            return 1
        }
        let isInFlightAfterFirst = await flight.isInFlight("k")
        let second = try await flight.execute(key: "k") {
            await executions.increment()
            return 2
        }

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        XCTAssertFalse(isInFlightAfterFirst)
        let count = await executions.value
        XCTAssertEqual(count, 2)
    }

    func testIsInFlightAndCountReflectActiveWork() async throws {
        let flight = SingleFlight<String, Int>()
        let gate = Gate()

        let task = Task {
            try await flight.execute(key: "k") {
                await gate.waitUntilOpened()
                return 1
            }
        }

        // Give the task a moment to register itself as in-flight.
        try await Task.sleep(nanoseconds: 30_000_000)
        let isInFlight = await flight.isInFlight("k")
        let count = await flight.inFlightCount
        XCTAssertTrue(isInFlight)
        XCTAssertEqual(count, 1)

        await gate.open()
        _ = try await task.value

        let isInFlightAfter = await flight.isInFlight("k")
        let countAfter = await flight.inFlightCount
        XCTAssertFalse(isInFlightAfter)
        XCTAssertEqual(countAfter, 0)
    }

    func testCancelThrowsCancellationErrorToCaller() async {
        let flight = SingleFlight<String, Int>()

        let task = Task {
            try await flight.execute(key: "k") {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await flight.cancel("k")

        let result = await task.result
        switch result {
        case .success:
            XCTFail("Expected cancellation to throw")
        case .failure:
            break // CancellationError or a wrapped variant, both acceptable.
        }
        let isInFlight = await flight.isInFlight("k")
        XCTAssertFalse(isInFlight)
    }

    func testCancelAllClearsEveryKey() async {
        let flight = SingleFlight<String, Int>()

        let taskA = Task {
            try await flight.execute(key: "a") {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        let taskB = Task {
            try await flight.execute(key: "b") {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 2
            }
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        await flight.cancelAll()

        let resultA = await taskA.result
        let resultB = await taskB.result
        XCTAssertThrowsErrorResult(resultA)
        XCTAssertThrowsErrorResult(resultB)
        let count = await flight.inFlightCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Helpers

    private func XCTAssertThrowsErrorResult(_ result: Result<Int, Error>) {
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure:
            break
        }
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private actor Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func open() {
            opened = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }

        func waitUntilOpened() async {
            if opened { return }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
}
