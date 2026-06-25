//
//  ConcurrentMapTests.swift
//  SwiftUtilsTests
//
//  Created by Pawan on 2026-06-25.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class ConcurrentMapTests: XCTestCase {

    // MARK: - concurrentMap

    func testConcurrentMapPreservesOrder() async throws {
        let input = Array(0..<20)
        let results = try await input.concurrentMap { value in
            // Reverse delay so later elements would finish first if order
            // weren't being reassembled correctly.
            try await Task.sleep(nanoseconds: UInt64((20 - value)) * 1_000_000)
            return value * 2
        }
        XCTAssertEqual(results, input.map { $0 * 2 })
    }

    func testConcurrentMapOnEmptySequenceReturnsEmpty() async throws {
        let input: [Int] = []
        let results = try await input.concurrentMap { $0 * 2 }
        XCTAssertTrue(results.isEmpty)
    }

    func testConcurrentMapRespectsMaxConcurrency() async throws {
        let limit = 3
        var peak = 0
        var current = 0
        let lock = NSLock()

        _ = try await (0..<12).concurrentMap(maxConcurrency: limit) { value -> Int in
            lock.lock()
            current += 1
            peak = max(peak, current)
            lock.unlock()

            try await Task.sleep(nanoseconds: 15_000_000) // 15 ms

            lock.lock()
            current -= 1
            lock.unlock()
            return value
        }

        XCTAssertLessThanOrEqual(peak, limit, "Peak concurrency \(peak) exceeded limit \(limit)")
    }

    func testConcurrentMapPropagatesFirstError() async {
        struct TestError: Error, Equatable { let id: Int }

        do {
            _ = try await (0..<10).concurrentMap { value in
                if value == 5 { throw TestError(id: value) }
                try await Task.sleep(nanoseconds: 5_000_000)
                return value
            }
            XCTFail("Expected error not thrown")
        } catch is TestError {
            // expected — at least one element throws
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - concurrentForEach

    func testConcurrentForEachVisitsAllElements() async throws {
        let input = Array(0..<15)
        let visited = ActorBox<Set<Int>>(Set())

        try await input.concurrentForEach(maxConcurrency: 4) { value in
            await visited.insert(value)
        }

        let result = await visited.value
        XCTAssertEqual(result, Set(input))
    }

    // MARK: - concurrentCompactMap

    func testConcurrentCompactMapDropsNils() async throws {
        let input = Array(0..<10)
        let results = try await input.concurrentCompactMap { value -> Int? in
            value.isMultiple(of: 2) ? value : nil
        }
        XCTAssertEqual(results, [0, 2, 4, 6, 8])
    }

    // MARK: - ConcurrentRace

    func testFirstSuccessReturnsFastestWinner() async throws {
        let result = try await ConcurrentRace.firstSuccess([
            {
                try await Task.sleep(nanoseconds: 100_000_000)
                return "slow"
            },
            {
                try await Task.sleep(nanoseconds: 5_000_000)
                return "fast"
            },
        ])
        XCTAssertEqual(result, "fast")
    }

    func testFirstSuccessSkipsFailuresAndReturnsWinner() async throws {
        struct TestError: Error {}

        let result = try await ConcurrentRace.firstSuccess([
            {
                throw TestError()
            },
            {
                try await Task.sleep(nanoseconds: 10_000_000)
                return 42
            },
        ])
        XCTAssertEqual(result, 42)
    }

    func testFirstSuccessThrowsWhenAllFail() async {
        struct TestError: Error, Equatable { let id: Int }

        do {
            let _: Int = try await ConcurrentRace.firstSuccess([
                { throw TestError(id: 1) },
                { throw TestError(id: 2) },
            ])
            XCTFail("Expected error not thrown")
        } catch is TestError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFirstSuccessThrowsNoOperationsForEmptyArray() async {
        do {
            let _: Int = try await ConcurrentRace.firstSuccess([])
            XCTFail("Expected error not thrown")
        } catch ConcurrentRaceError.noOperations {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

/// Minimal actor box used to safely accumulate results from concurrent tasks
/// within these tests.
private actor ActorBox<Value> {
    private(set) var value: Value
    init(_ value: Value) { self.value = value }
}

private extension ActorBox where Value == Set<Int> {
    func insert(_ element: Int) {
        value.insert(element)
    }
}
