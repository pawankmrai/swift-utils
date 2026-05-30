import XCTest
@testable import SwiftUtilsNetworking

final class NetworkRetrierTests: XCTestCase {

    // MARK: - DelayStrategy Tests

    func testFixedDelay() {
        let strategy = DelayStrategy.fixed(delay: 2.0)
        XCTAssertEqual(strategy.delay(forAttempt: 0), 2.0)
        XCTAssertEqual(strategy.delay(forAttempt: 5), 2.0)
    }

    func testExponentialDelay() {
        let strategy = DelayStrategy.exponential(base: 1.0, multiplier: 2.0, maxDelay: 30.0)
        XCTAssertEqual(strategy.delay(forAttempt: 0), 1.0)  // 1 * 2^0
        XCTAssertEqual(strategy.delay(forAttempt: 1), 2.0)  // 1 * 2^1
        XCTAssertEqual(strategy.delay(forAttempt: 2), 4.0)  // 1 * 2^2
        XCTAssertEqual(strategy.delay(forAttempt: 3), 8.0)  // 1 * 2^3
    }

    func testExponentialDelayRespectsCap() {
        let strategy = DelayStrategy.exponential(base: 1.0, multiplier: 2.0, maxDelay: 5.0)
        XCTAssertEqual(strategy.delay(forAttempt: 10), 5.0)
    }

    func testExponentialWithJitterInRange() {
        let strategy = DelayStrategy.exponentialWithJitter(base: 1.0, multiplier: 2.0, maxDelay: 60.0, jitterRange: 1.0)
        let delay = strategy.delay(forAttempt: 0)
        // base * 2^0 = 1.0, jitter in 0...1.0, so delay in 1.0...2.0
        XCTAssertGreaterThanOrEqual(delay, 1.0)
        XCTAssertLessThanOrEqual(delay, 2.0)
    }

    func testCustomDelay() {
        let strategy = DelayStrategy.custom { attempt in Double(attempt) * 0.5 }
        XCTAssertEqual(strategy.delay(forAttempt: 0), 0.0)
        XCTAssertEqual(strategy.delay(forAttempt: 4), 2.0)
    }

    // MARK: - RetryPolicy Tests

    func testMaxAttemptsClampsToOne() {
        let policy = RetryPolicy(maxAttempts: -5)
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    func testDefaultShouldRetryWithURLError() {
        let timedOut = URLError(.timedOut)
        XCTAssertTrue(RetryPolicy.defaultShouldRetry(timedOut))

        let cancelled = URLError(.cancelled)
        XCTAssertFalse(RetryPolicy.defaultShouldRetry(cancelled))
    }

    func testDefaultShouldRetryWithNonURLError() {
        struct CustomError: Error {}
        XCTAssertFalse(RetryPolicy.defaultShouldRetry(CustomError()))
    }

    func testPresets() {
        XCTAssertEqual(RetryPolicy.aggressive.maxAttempts, 5)
        XCTAssertEqual(RetryPolicy.conservative.maxAttempts, 3)
        XCTAssertEqual(RetryPolicy.once.maxAttempts, 2)
        XCTAssertEqual(RetryPolicy.none.maxAttempts, 1)
    }

    // MARK: - NetworkRetrier.execute Tests

    func testSucceedsOnFirstAttempt() async throws {
        let result = try await NetworkRetrier.execute(policy: .none) {
            42
        }
        XCTAssertEqual(result, 42)
    }

    func testRetriesAndSucceeds() async throws {
        let counter = Counter()
        let result = try await NetworkRetrier.execute(
            policy: RetryPolicy(maxAttempts: 3, strategy: .fixed(delay: 0.01))
        ) {
            let current = await counter.increment()
            if current < 3 {
                throw URLError(.timedOut)
            }
            return "success"
        }
        XCTAssertEqual(result, "success")
        let finalCount = await counter.value
        XCTAssertEqual(finalCount, 3)
    }

    func testThrowsRetryExhaustedAfterMaxAttempts() async {
        let counter = Counter()
        do {
            _ = try await NetworkRetrier.execute(
                policy: RetryPolicy(maxAttempts: 2, strategy: .fixed(delay: 0.01))
            ) {
                await counter.increment()
                throw URLError(.timedOut)
            }
            XCTFail("Should have thrown")
        } catch let error as RetryExhaustedError {
            XCTAssertEqual(error.attempts, 2)
            XCTAssertTrue(error.lastError is URLError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        let finalCount = await counter.value
        XCTAssertEqual(finalCount, 2)
    }

    func testNonRetryableErrorThrowsImmediately() async {
        struct NonRetryable: Error {}
        let counter = Counter()
        do {
            _ = try await NetworkRetrier.execute(
                policy: RetryPolicy(maxAttempts: 5, strategy: .fixed(delay: 0.01))
            ) {
                await counter.increment()
                throw NonRetryable()
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is NonRetryable)
        }
        let finalCount = await counter.value
        XCTAssertEqual(finalCount, 1)
    }

    // MARK: - Error description tests

    func testRetryExhaustedErrorDescription() {
        let error = RetryExhaustedError(lastError: URLError(.timedOut), attempts: 3)
        XCTAssertTrue(error.localizedDescription.contains("3"))
    }

    func testHTTPRetryableStatusErrorDescription() {
        let error = HTTPRetryableStatusError(statusCode: 503)
        XCTAssertTrue(error.localizedDescription.contains("503"))
    }
}

// MARK: - Helpers

private actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
