//
//  AsyncSequenceCombiningTests.swift
//  SwiftUtilsTests
//
//  Created by Pawan on 2026-07-26.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncSequenceCombiningTests: XCTestCase {

    private struct SampleError: Error, Equatable {}

    // MARK: - merge

    func testMergeInterleavesAllElementsFromBothSources() async throws {
        let a = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.finish()
        }
        let b = AsyncStream<Int> { continuation in
            continuation.yield(10)
            continuation.yield(20)
            continuation.finish()
        }

        var collected: [Int] = []
        for try await value in merge(a, b) {
            collected.append(value)
        }

        XCTAssertEqual(collected.sorted(), [1, 2, 10, 20])
    }

    func testMergeArrayOverloadFinishesWithNoSequences() async throws {
        let empty: [AsyncStream<Int>] = []
        var collected: [Int] = []
        for try await value in merge(empty) {
            collected.append(value)
        }
        XCTAssertTrue(collected.isEmpty)
    }

    func testMergePropagatesErrorFromEitherSource() async {
        let throwing = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: SampleError())
        }
        let clean = AsyncStream<Int> { continuation in
            continuation.finish()
        }

        do {
            for try await _ in merge(throwing, clean) {}
            XCTFail("Expected SampleError to propagate")
        } catch is SampleError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - combineLatest

    func testCombineLatestEmitsOnceBothSourcesHaveAValue() async throws {
        // `a` yields 1, then (after `b` has had a chance to yield "x") yields 2.
        let a = AsyncStream<Int> { continuation in
            Task {
                continuation.yield(1)
                try? await Task.sleep(nanoseconds: 30_000_000)
                continuation.yield(2)
                continuation.finish()
            }
        }
        let b = AsyncStream<String> { continuation in
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000)
                continuation.yield("x")
                continuation.finish()
            }
        }

        var results: [(Int, String)] = []
        for try await pair in combineLatest(a, b) {
            results.append(pair)
        }

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].0, 1)
        XCTAssertEqual(results[0].1, "x")
        XCTAssertEqual(results[1].0, 2)
        XCTAssertEqual(results[1].1, "x")
    }

    func testCombineLatestEmitsNothingUntilBothSidesHaveAValue() async throws {
        let a = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.finish()
            // `b` never yields, so no pair should ever be produced.
        }
        let b = AsyncStream<String> { continuation in
            continuation.finish()
        }

        var results: [(Int, String)] = []
        for try await pair in combineLatest(a, b) {
            results.append(pair)
        }

        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - zip

    func testZipPairsElementsInLockstep() async throws {
        let a = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }
        let b = AsyncStream<String> { continuation in
            continuation.yield("a")
            continuation.yield("b")
            continuation.finish()
        }

        var pairs: [(Int, String)] = []
        for try await pair in zip(a, b) {
            pairs.append(pair)
        }

        // Shorter source (b, 2 elements) determines the stream length.
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 1)
        XCTAssertEqual(pairs[0].1, "a")
        XCTAssertEqual(pairs[1].0, 2)
        XCTAssertEqual(pairs[1].1, "b")
    }
}
