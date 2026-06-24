//
//  AsyncTimeoutTests.swift
//  SwiftUtilsTests
//
//  Created by Pawan on 2026-06-24.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncTimeoutTests: XCTestCase {

    private struct SampleError: Error, Equatable {}

    // MARK: - Operation finishes before timeout

    func testOperationCompletesBeforeTimeout() async throws {
        let result = try await withTimeout(seconds: 1) {
            try await Task.sleep(nanoseconds: 10_000_000) // 10 ms
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    // MARK: - Timeout fires before operation completes

    func testTimeoutFiresWhenOperationIsSlow() async {
        do {
            _ = try await withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
                return "too slow"
            }
            XCTFail("Expected TimeoutError to be thrown")
        } catch let error as TimeoutError {
            XCTAssertEqual(error.seconds, 0.05)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Operation error propagates (not masked as a timeout)

    func testOperationErrorPropagates() async {
        do {
            _ = try await withTimeout(seconds: 1) {
                throw SampleError()
            }
            XCTFail("Expected SampleError to be thrown")
        } catch is SampleError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - TimeoutError description

    func testTimeoutErrorDescription() {
        let error = TimeoutError(seconds: 3)
        XCTAssertEqual(error.errorDescription, "Operation timed out after 3.0 second(s).")
    }

    // MARK: - withTimeout(default:)

    func testDefaultValueReturnedOnTimeout() async {
        let value = await withTimeout(seconds: 0.05, default: -1) {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return 99
        }
        XCTAssertEqual(value, -1)
    }

    func testDefaultValueNotUsedWhenOperationSucceeds() async {
        let value = await withTimeout(seconds: 1, default: -1) {
            99
        }
        XCTAssertEqual(value, 99)
    }

    func testDefaultValueReturnedWhenOperationThrows() async {
        let value = await withTimeout(seconds: 1, default: -1) {
            throw SampleError()
        }
        XCTAssertEqual(value, -1)
    }

    // MARK: - withTimeoutOrNil

    func testWithTimeoutOrNilReturnsNilOnTimeout() async throws {
        let value = try await withTimeoutOrNil(seconds: 0.05) {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return "late"
        }
        XCTAssertNil(value)
    }

    func testWithTimeoutOrNilReturnsValueOnSuccess() async throws {
        let value = try await withTimeoutOrNil(seconds: 1) {
            "on time"
        }
        XCTAssertEqual(value, "on time")
    }

    func testWithTimeoutOrNilRethrowsNonTimeoutErrors() async {
        do {
            _ = try await withTimeoutOrNil(seconds: 1) {
                throw SampleError()
            }
            XCTFail("Expected SampleError to be thrown")
        } catch is SampleError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
