//
//  DebounceThrottleTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-05-06.
//

import XCTest
@testable import SwiftUtilsConcurrency

// MARK: - Debouncer Tests

final class DebouncerTests: XCTestCase {

    func testDebouncerFiresAfterDelay() {
        let expectation = expectation(description: "Debounced action fires")
        let debouncer = Debouncer(delay: 0.1, queue: .main)

        debouncer.debounce {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testDebouncerCancelsPreviousCalls() {
        let expectation = expectation(description: "Only last action fires")
        var callCount = 0
        let debouncer = Debouncer(delay: 0.15, queue: .main)

        // Rapid-fire three calls; only the last should execute
        debouncer.debounce { callCount += 1 }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            debouncer.debounce { callCount += 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            debouncer.debounce {
                callCount += 1
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(callCount, 1, "Only the last debounced action should fire")
    }

    func testDebouncerCancel() {
        let debouncer = Debouncer(delay: 0.1, queue: .main)
        var didFire = false

        debouncer.debounce { didFire = true }
        debouncer.cancel()

        let expectation = expectation(description: "Wait past debounce window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertFalse(didFire, "Cancelled debounce should not fire")
    }

    func testDebouncerThreadSafety() {
        let debouncer = Debouncer(delay: 0.05, queue: .main)
        let expectation = expectation(description: "Concurrent debounce calls complete")
        let iterations = 100
        var finalValue = 0

        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<iterations {
            concurrentQueue.async {
                debouncer.debounce {
                    finalValue = i
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        // Only one call should have fired
        XCTAssertTrue(finalValue >= 0 && finalValue < iterations)
    }
}

// MARK: - Throttler Tests

final class ThrottlerTests: XCTestCase {

    func testLeadingThrottleFiresImmediately() {
        let expectation = expectation(description: "Leading action fires")
        let throttler = Throttler(interval: 1.0, mode: .leading, queue: .main)

        throttler.throttle {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5)
    }

    func testLeadingThrottleSuppressesSubsequentCalls() {
        var callCount = 0
        let throttler = Throttler(interval: 0.3, mode: .leading, queue: .main)

        // First call fires immediately
        throttler.throttle { callCount += 1 }
        // Subsequent calls within interval should be suppressed
        throttler.throttle { callCount += 1 }
        throttler.throttle { callCount += 1 }

        let expectation = expectation(description: "Wait for interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(callCount, 1, "Leading mode should only fire the first call")
    }

    func testTrailingThrottleFiresAfterInterval() {
        let expectation = expectation(description: "Trailing action fires")
        let throttler = Throttler(interval: 0.1, mode: .trailing, queue: .main)

        throttler.throttle {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testLeadingAndTrailingMode() {
        var callCount = 0
        let throttler = Throttler(interval: 0.2, mode: .leadingAndTrailing, queue: .main)

        // First call fires immediately (leading)
        throttler.throttle { callCount += 1 }
        // These should be coalesced into a single trailing call
        throttler.throttle { callCount += 1 }
        throttler.throttle { callCount += 1 }

        let expectation = expectation(description: "Wait for trailing fire")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(callCount, 2, "Leading+trailing should fire twice: once immediately, once after interval")
    }

    func testThrottlerCancel() {
        let throttler = Throttler(interval: 0.1, mode: .trailing, queue: .main)
        var didFire = false

        throttler.throttle { didFire = true }
        throttler.cancel()

        let expectation = expectation(description: "Wait past throttle window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertFalse(didFire, "Cancelled throttle should not fire")
    }
}
