//
//  AuthTokenRefresherTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-24.
//

import XCTest
@testable import SwiftUtilsNetworking

/// A `URLProtocol` stub that serves a queue of status codes (one per
/// request) and records the `Authorization` header seen on each request, so
/// tests can assert on 401-triggered retry behavior.
private final class MockAuthURLProtocol: URLProtocol {
    private static var statusCodes: [Int] = []
    private static var seenAuthHeaders: [String] = []
    private static let lock = NSLock()

    static func enqueue(_ codes: [Int]) {
        lock.lock(); statusCodes = codes; seenAuthHeaders = []; lock.unlock()
    }

    static var authHeaders: [String] {
        lock.lock(); defer { lock.unlock() }
        return seenAuthHeaders
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let code = Self.statusCodes.isEmpty ? 200 : Self.statusCodes.removeFirst()
        Self.seenAuthHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: code,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AuthTokenRefresherTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAuthURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeRequest() -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.com/resource")!)
    }

    // MARK: - Caching

    func testCachedValidTokenIsReusedWithoutRefreshing() async throws {
        var refreshCount = 0
        let token = AuthToken(accessToken: "cached", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(initialToken: token) {
            refreshCount += 1
            return AuthToken(accessToken: "new", expiresAt: Date().addingTimeInterval(3600))
        }

        let result = try await refresher.validToken()

        XCTAssertEqual(result.accessToken, "cached")
        XCTAssertEqual(refreshCount, 0)
    }

    func testMissingTokenTriggersRefresh() async throws {
        let refresher = AuthTokenRefresher {
            AuthToken(accessToken: "fresh", expiresAt: Date().addingTimeInterval(3600))
        }

        let result = try await refresher.validToken()

        XCTAssertEqual(result.accessToken, "fresh")
    }

    func testExpiredTokenTriggersRefresh() async throws {
        let stale = AuthToken(accessToken: "stale", expiresAt: Date().addingTimeInterval(-10))
        let refresher = AuthTokenRefresher(initialToken: stale) {
            AuthToken(accessToken: "rotated", expiresAt: Date().addingTimeInterval(3600))
        }

        let result = try await refresher.validToken()

        XCTAssertEqual(result.accessToken, "rotated")
    }

    // MARK: - Single-flight refresh

    func testConcurrentCallsShareOneRefresh() async throws {
        let refreshCount = Counter()
        let refresher = AuthTokenRefresher {
            await refreshCount.increment()
            try? await Task.sleep(nanoseconds: 20_000_000)
            return AuthToken(accessToken: "shared", expiresAt: Date().addingTimeInterval(3600))
        }

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask { try await refresher.validToken().accessToken }
            }
            var collected: [String] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        XCTAssertEqual(results, Array(repeating: "shared", count: 10))
        let count = await refreshCount.value
        XCTAssertEqual(count, 1)
    }

    // MARK: - Manual control

    func testInvalidateForcesNextRefresh() async throws {
        var refreshCount = 0
        let token = AuthToken(accessToken: "cached", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(initialToken: token) {
            refreshCount += 1
            return AuthToken(accessToken: "rotated-\(refreshCount)", expiresAt: Date().addingTimeInterval(3600))
        }

        await refresher.invalidate()
        let result = try await refresher.validToken()

        XCTAssertEqual(result.accessToken, "rotated-1")
        XCTAssertEqual(refreshCount, 1)
    }

    func testSetTokenSeedsCache() async throws {
        let refresher = AuthTokenRefresher {
            XCTFail("refresh should not be called when a token was just set")
            return AuthToken(accessToken: "unused", expiresAt: Date())
        }

        await refresher.setToken(AuthToken(accessToken: "seeded", expiresAt: Date().addingTimeInterval(3600)))
        let result = try await refresher.validToken()

        XCTAssertEqual(result.accessToken, "seeded")
    }

    func testCachedTokenReflectsCurrentState() async throws {
        let refresher = AuthTokenRefresher {
            AuthToken(accessToken: "fresh", expiresAt: Date().addingTimeInterval(3600))
        }

        let before = await refresher.cachedToken
        XCTAssertNil(before)

        _ = try await refresher.validToken()
        let after = await refresher.cachedToken
        XCTAssertEqual(after?.accessToken, "fresh")
    }

    // MARK: - Authorization

    func testAuthorizeAttachesBearerHeaderByDefault() async throws {
        let token = AuthToken(accessToken: "abc123", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(initialToken: token) {
            AuthToken(accessToken: "unused", expiresAt: Date())
        }

        let authorized = try await refresher.authorize(makeRequest())

        XCTAssertEqual(authorized.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testAuthorizeRespectsCustomHeaderFieldAndPrefix() async throws {
        let token = AuthToken(accessToken: "xyz", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(
            initialToken: token,
            headerField: "X-Api-Token",
            headerPrefix: "Token "
        ) {
            AuthToken(accessToken: "unused", expiresAt: Date())
        }

        let authorized = try await refresher.authorize(makeRequest())

        XCTAssertEqual(authorized.value(forHTTPHeaderField: "X-Api-Token"), "Token xyz")
        XCTAssertNil(authorized.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - execute(_:using:)

    func testExecuteSucceedsOnFirstTryWithoutRetry() async throws {
        MockAuthURLProtocol.enqueue([200])
        let token = AuthToken(accessToken: "good-token", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(initialToken: token) {
            XCTFail("refresh should not be needed")
            return AuthToken(accessToken: "unused", expiresAt: Date())
        }

        let (_, response) = try await refresher.execute(makeRequest(), using: makeSession())

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(MockAuthURLProtocol.authHeaders, ["Bearer good-token"])
    }

    func testExecuteRetriesOnceAfter401WithRefreshedToken() async throws {
        MockAuthURLProtocol.enqueue([401, 200])
        var refreshCount = 0
        let stale = AuthToken(accessToken: "stale-token", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(initialToken: stale) {
            refreshCount += 1
            return AuthToken(accessToken: "rotated-token", expiresAt: Date().addingTimeInterval(3600))
        }

        let (_, response) = try await refresher.execute(makeRequest(), using: makeSession())

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(MockAuthURLProtocol.authHeaders, ["Bearer stale-token", "Bearer rotated-token"])
        let cached = await refresher.cachedToken
        XCTAssertEqual(cached?.accessToken, "rotated-token")
    }

    func testExecuteDoesNotLoopOnRepeated401() async throws {
        MockAuthURLProtocol.enqueue([401, 401])
        var refreshCount = 0
        let token = AuthToken(accessToken: "bad-token", expiresAt: Date().addingTimeInterval(3600))
        let refresher = AuthTokenRefresher(initialToken: token) {
            refreshCount += 1
            return AuthToken(accessToken: "still-bad", expiresAt: Date().addingTimeInterval(3600))
        }

        let (_, response) = try await refresher.execute(makeRequest(), using: makeSession())

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(MockAuthURLProtocol.authHeaders.count, 2)
    }

    // MARK: - Errors

    func testRefreshFailurePropagatesAsAuthTokenError() async {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "network unreachable" }
        }
        let refresher = AuthTokenRefresher {
            throw DummyError()
        }

        do {
            _ = try await refresher.validToken()
            XCTFail("expected refresh to throw")
        } catch let AuthTokenError.refreshFailed(underlying) {
            XCTAssertEqual((underlying as? DummyError)?.errorDescription, "network unreachable")
        } catch {
            XCTFail("expected AuthTokenError.refreshFailed, got \(error)")
        }
    }

    func testIsValidRespectsLeeway() {
        let almostExpired = AuthToken(accessToken: "t", expiresAt: Date().addingTimeInterval(10))
        XCTAssertTrue(almostExpired.isValid(leeway: 5))
        XCTAssertFalse(almostExpired.isValid(leeway: 30))
    }
}

/// A tiny actor for thread-safe counting in concurrency tests.
private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
