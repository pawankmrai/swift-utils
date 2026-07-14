//
//  AsyncRateLimiterTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-14.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncRateLimiterTests: XCTestCase {

    func testInitialBurstIsFullCapacity() async {
        let limiter = AsyncRateLimiter(capacity: 3, refillInterval: 1)
        let available = await limiter.availableTokens
        XCTAssertEqual(available, 3, accuracy: 0.01)
    }

    func testTryAcquireConsumesTokensUpToCapacity() async {
        let limiter = AsyncRateLimiter(capacity: 2, refillInterval: 10)

        let first = await limiter.tryAcquire()
        let second = await limiter.tryAcquire()
        let third = await limiter.tryAcquire()

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertFalse(third, "Bucket should be empty after consuming its full capacity")
    }

    func testTryAcquireDoesNotSuspend() async {
        let limiter = AsyncRateLimiter(capacity: 1, refillInterval: 60)
        _ = await limiter.tryAcquire()

        // A second call should return false immediately rather than waiting.
        let start = DispatchTime.now()
        let result = await limiter.tryAcquire()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000

        XCTAssertFalse(result)
        XCTAssertLessThan(elapsedMs, 50, "tryAcquire must not block waiting for refill")
    }

    func testAcquireSuspendsUntilRefill() async throws {
        // 10 tokens/sec -> a single token refills in ~100ms.
        let limiter = AsyncRateLimiter(capacity: 1, refillInterval: 0.1)
        try await limiter.acquire() // drains the initial burst

        let start = DispatchTime.now()
        try await limiter.acquire() // must wait for a refill
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000

        XCTAssertGreaterThanOrEqual(elapsedMs, 40, "acquire() should have suspended waiting for a token")
    }

    func testTokensRefillOverTimeUpToCapacity() async throws {
        let limiter = AsyncRateLimiter(capacity: 5, refillInterval: 1) // 5 tokens/sec
        for _ in 0..<5 { _ = await limiter.tryAcquire() }

        var drained = await limiter.availableTokens
        XCTAssertEqual(drained, 0, accuracy: 0.01)

        try await Task.sleep(nanoseconds: 300_000_000) // ~0.3s -> ~1.5 tokens back
        drained = await limiter.availableTokens
        XCTAssertGreaterThan(drained, 1.0)
        XCTAssertLessThan(drained, 5.0)
    }

    func testRefillNeverExceedsCapacity() async throws {
        let limiter = AsyncRateLimiter(capacity: 2, refillInterval: 0.05)
        try await Task.sleep(nanoseconds: 500_000_000) // plenty of time to overfill
        let available = await limiter.availableTokens
        XCTAssertEqual(available, 2, accuracy: 0.01)
    }

    func testWithThrottleReturnsOperationResult() async throws {
        let limiter = AsyncRateLimiter(capacity: 2, refillInterval: 1)
        let value = try await limiter.withThrottle { 42 }
        XCTAssertEqual(value, 42)
    }

    func testWithThrottlePropagatesOperationError() async {
        let limiter = AsyncRateLimiter(capacity: 2, refillInterval: 1)
        struct Boom: Error {}

        do {
            _ = try await limiter.withThrottle { () -> Int in throw Boom() }
            XCTFail("Expected error to propagate")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAcquireThrowsOnCancellation() async {
        let limiter = AsyncRateLimiter(capacity: 1, refillInterval: 60)
        _ = await limiter.tryAcquire() // drain the only token

        let task = Task {
            try await limiter.acquire()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            XCTFail("Expected cancellation to throw before a token became available")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testAcquireIgnoringCancellationDoesNotThrow() async {
        let limiter = AsyncRateLimiter(capacity: 1, refillInterval: 0.05)
        await limiter.acquireIgnoringCancellation()
        await limiter.acquireIgnoringCancellation() // should just wait, not throw
    }

    func testMaxCapacityReflectsInitializer() async {
        let limiter = AsyncRateLimiter(capacity: 7, refillInterval: 1)
        let cap = await limiter.maxCapacity
        XCTAssertEqual(cap, 7)
    }
}
