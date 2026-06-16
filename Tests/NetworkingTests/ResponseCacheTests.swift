import XCTest
@testable import SwiftUtilsNetworking

private struct Quote: Codable, Sendable, Equatable {
    let text: String
}

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

final class ResponseCacheTests: XCTestCase {

    private func makeCache(
        namespace: String = UUID().uuidString,
        persistToDisk: Bool = false,
        defaultTTL: TimeInterval? = nil
    ) -> ResponseCache<Quote> {
        ResponseCache<Quote>(namespace: namespace, persistToDisk: persistToDisk, defaultTTL: defaultTTL)
    }

    // MARK: - Basic store/retrieve

    func testStoreAndRetrieveValue() async {
        let cache = makeCache()
        let quote = Quote(text: "Stay hungry, stay foolish.")

        await cache.store(quote, for: "q1")
        let result = await cache.value(for: "q1")

        XCTAssertEqual(result, quote)
    }

    func testMissingKeyReturnsNil() async {
        let cache = makeCache()
        let result = await cache.value(for: "missing")
        XCTAssertNil(result)
    }

    func testOverwritingExistingKey() async {
        let cache = makeCache()
        await cache.store(Quote(text: "first"), for: "q1")
        await cache.store(Quote(text: "second"), for: "q1")

        let result = await cache.value(for: "q1")
        XCTAssertEqual(result?.text, "second")
    }

    // MARK: - Expiration

    func testEntryExpiresAfterTTL() async throws {
        let cache = makeCache()
        await cache.store(Quote(text: "ephemeral"), for: "q1", ttl: 0.05)

        let immediate = await cache.value(for: "q1")
        XCTAssertEqual(immediate?.text, "ephemeral")

        try await Task.sleep(nanoseconds: 150_000_000)

        let afterExpiry = await cache.value(for: "q1")
        XCTAssertNil(afterExpiry)
    }

    func testDefaultTTLAppliesWhenNoneSpecified() async throws {
        let cache = makeCache(defaultTTL: 0.05)
        await cache.store(Quote(text: "ephemeral"), for: "q1")

        try await Task.sleep(nanoseconds: 150_000_000)

        let result = await cache.value(for: "q1")
        XCTAssertNil(result)
    }

    func testNilTTLNeverExpires() async {
        let cache = makeCache()
        await cache.store(Quote(text: "forever"), for: "q1", ttl: nil)
        let result = await cache.value(for: "q1")
        XCTAssertEqual(result?.text, "forever")
    }

    func testEvictExpiredRemovesOnlyExpiredEntries() async throws {
        let cache = makeCache()
        await cache.store(Quote(text: "expired"), for: "old", ttl: 0.01)
        await cache.store(Quote(text: "fresh"), for: "new", ttl: 100)

        try await Task.sleep(nanoseconds: 50_000_000)

        let evicted = await cache.evictExpired()
        XCTAssertEqual(evicted, 1)

        let count = await cache.count
        XCTAssertEqual(count, 1)
        let remaining = await cache.value(for: "new")
        XCTAssertEqual(remaining?.text, "fresh")
    }

    // MARK: - Invalidation

    func testInvalidateRemovesEntry() async {
        let cache = makeCache()
        await cache.store(Quote(text: "temp"), for: "q1")
        await cache.invalidate("q1")

        let result = await cache.value(for: "q1")
        XCTAssertNil(result)
    }

    func testRemoveAllClearsEverything() async {
        let cache = makeCache()
        await cache.store(Quote(text: "a"), for: "q1")
        await cache.store(Quote(text: "b"), for: "q2")

        await cache.removeAll()

        let count = await cache.count
        XCTAssertEqual(count, 0)
        let a = await cache.value(for: "q1")
        let b = await cache.value(for: "q2")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }

    // MARK: - Get-or-fetch

    func testValueForKeyFetchCalledOnceOnCacheMiss() async throws {
        let cache = makeCache()
        let counter = CallCounter()

        let result = try await cache.value(for: "q1") {
            await counter.increment()
            return Quote(text: "fetched")
        }

        XCTAssertEqual(result.text, "fetched")
        let callCount = await counter.count
        XCTAssertEqual(callCount, 1)
    }

    func testValueForKeyFetchNotCalledOnCacheHit() async throws {
        let cache = makeCache()
        let counter = CallCounter()
        await cache.store(Quote(text: "cached"), for: "q1")

        let result = try await cache.value(for: "q1") {
            await counter.increment()
            return Quote(text: "fetched")
        }

        XCTAssertEqual(result.text, "cached")
        let callCount = await counter.count
        XCTAssertEqual(callCount, 0)
    }

    func testValueForKeyFetchPropagatesErrors() async {
        struct FetchError: Error {}
        let cache = makeCache()

        do {
            _ = try await cache.value(for: "q1") {
                throw FetchError()
            }
            XCTFail("Expected fetch error to propagate")
        } catch is FetchError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Disk persistence

    func testDiskPersistenceSurvivesNewInstance() async {
        let namespace = "test-\(UUID().uuidString)"
        let quote = Quote(text: "persisted")

        let writer = ResponseCache<Quote>(namespace: namespace, persistToDisk: true)
        await writer.store(quote, for: "q1")

        let reader = ResponseCache<Quote>(namespace: namespace, persistToDisk: true)
        let result = await reader.value(for: "q1")

        XCTAssertEqual(result, quote)

        await reader.removeAll()
    }

    func testDisabledDiskPersistenceDoesNotSurvive() async {
        let namespace = "test-\(UUID().uuidString)"
        let writer = ResponseCache<Quote>(namespace: namespace, persistToDisk: false)
        await writer.store(Quote(text: "memory-only"), for: "q1")

        let reader = ResponseCache<Quote>(namespace: namespace, persistToDisk: false)
        let result = await reader.value(for: "q1")

        XCTAssertNil(result)
    }
}
