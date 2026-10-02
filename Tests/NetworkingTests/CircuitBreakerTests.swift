//
//  CircuitBreakerTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-10-02.
//

import XCTest
@testable import SwiftUtilsNetworking

/// A manually advanced clock for deterministic timeout tests.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current += seconds; lock.unlock() }
}

private struct TestError: Error {}

final class CircuitBreakerTests: XCTestCase {

    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeBreaker(failures: Int = 3,
                             timeout: TimeInterval = 10,
                             successes: Int = 1,
                             halfOpenMax: Int = 1) -> CircuitBreaker {
        let clock = self.clock!
        return CircuitBreaker(
            configuration: .init(failureThreshold: failures,
                                 resetTimeout: timeout,
                                 successThreshold: successes,
                                 halfOpenMaxCalls: halfOpenMax),
            now: { clock.now }
        )
    }

    private func fail(_ breaker: CircuitBreaker, times: Int) async {
        for _ in 0..<times {
            _ = try? await breaker.execute { () async throws -> Int in throw TestError() }
        }
    }

    func testStartsClosedAndPassesThroughValues() async throws {
        let breaker = makeBreaker()
        let value = try await breaker.execute { 42 }
        XCTAssertEqual(value, 42)
        let state = await breaker.state
        XCTAssertEqual(state, .closed)
    }

    func testTripsAfterFailureThreshold() async {
        let breaker = makeBreaker(failures: 3)
        await fail(breaker, times: 2)
        var state = await breaker.state
        XCTAssertEqual(state, .closed)

        await fail(breaker, times: 1)
        state = await breaker.state
        XCTAssertEqual(state, .open(until: clock.now.addingTimeInterval(10)))
    }

    func testSuccessResetsConsecutiveFailures() async throws {
        let breaker = makeBreaker(failures: 3)
        await fail(breaker, times: 2)
        _ = try await breaker.execute { 1 }
        let failures = await breaker.consecutiveFailures
        XCTAssertEqual(failures, 0)
    }

    func testOpenCircuitFailsFastWithoutRunningOperation() async {
        let breaker = makeBreaker(failures: 1, timeout: 10)
        await fail(breaker, times: 1)
        clock.advance(4)

        let ran = Recorder()
        do {
            _ = try await breaker.execute { () -> Int in ran.append(.closed); return 1 }
            XCTFail("Expected circuitOpen")
        } catch let error as CircuitBreakerError {
            XCTAssertEqual(error, .circuitOpen(retryAfter: 6))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        XCTAssertTrue(ran.values.isEmpty)
    }

    func testMovesToHalfOpenAfterTimeoutAndClosesOnSuccess() async throws {
        let breaker = makeBreaker(failures: 1, timeout: 10)
        await fail(breaker, times: 1)
        clock.advance(10)

        var state = await breaker.state
        XCTAssertEqual(state, .halfOpen)

        _ = try await breaker.execute { "ok" }
        state = await breaker.state
        XCTAssertEqual(state, .closed)
    }

    func testHalfOpenFailureReopens() async {
        let breaker = makeBreaker(failures: 1, timeout: 10)
        await fail(breaker, times: 1)
        clock.advance(10)
        await fail(breaker, times: 1)

        let state = await breaker.state
        XCTAssertEqual(state, .open(until: clock.now.addingTimeInterval(10)))
    }

    func testSuccessThresholdRequiresMultipleTrials() async throws {
        let breaker = makeBreaker(failures: 1, timeout: 5, successes: 2)
        await fail(breaker, times: 1)
        clock.advance(5)

        _ = try await breaker.execute { 1 }
        var state = await breaker.state
        XCTAssertEqual(state, .halfOpen)

        _ = try await breaker.execute { 2 }
        state = await breaker.state
        XCTAssertEqual(state, .closed)
    }

    func testIgnoredErrorsDoNotCount() async {
        let clock = self.clock!
        let breaker = CircuitBreaker(
            configuration: .init(failureThreshold: 1),
            isFailure: { !($0 is TestError) },
            now: { clock.now }
        )
        await fail(breaker, times: 5)
        let state = await breaker.state
        XCTAssertEqual(state, .closed)
    }

    func testCancellationErrorIsIgnoredByDefault() async {
        let breaker = makeBreaker(failures: 1)
        _ = try? await breaker.execute { () async throws -> Int in throw CancellationError() }
        let state = await breaker.state
        XCTAssertEqual(state, .closed)
    }

    func testManualTripAndReset() async {
        let breaker = makeBreaker(timeout: 30)
        await breaker.trip()
        var state = await breaker.state
        XCTAssertEqual(state, .open(until: clock.now.addingTimeInterval(30)))

        await breaker.reset()
        state = await breaker.state
        XCTAssertEqual(state, .closed)
    }

    func testObserverReceivesTransitions() async throws {
        let breaker = makeBreaker(failures: 1, timeout: 1)
        let recorded = Recorder()
        await breaker.onStateChange { recorded.append($0) }

        await fail(breaker, times: 1)
        clock.advance(1)
        _ = try await breaker.execute { 0 }

        let states = recorded.values
        XCTAssertEqual(states.count, 3)
        XCTAssertEqual(states[1], .halfOpen)
        XCTAssertEqual(states[2], .closed)
    }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CircuitBreaker.State] = []
    var values: [CircuitBreaker.State] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ state: CircuitBreaker.State) { lock.lock(); storage.append(state); lock.unlock() }
}
