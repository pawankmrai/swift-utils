import XCTest
@testable import SwiftUtilsStorage

final class LRUCacheTests: XCTestCase {

    // MARK: - Basic get/set

    func testSetAndGet() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        await cache.setValue(1, forKey: "a")
        let value = await cache.value(forKey: "a")
        XCTAssertEqual(value, 1)
    }

    func testMissingKeyReturnsNil() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        let value = await cache.value(forKey: "missing")
        XCTAssertNil(value)
    }

    func testUpdateExistingKeyDoesNotGrowCount() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        await cache.setValue(1, forKey: "a")
        await cache.setValue(2, forKey: "a")
        let count = await cache.count
        let value = await cache.value(forKey: "a")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(value, 2)
    }

    // MARK: - Eviction

    func testEvictsLeastRecentlyUsedWhenOverCapacity() async {
        let cache = LRUCache<String, Int>(capacity: 2)
        await cache.setValue(1, forKey: "a")
        await cache.setValue(2, forKey: "b")
        await cache.setValue(3, forKey: "c") // evicts "a"

        let a = await cache.value(forKey: "a")
        let b = await cache.value(forKey: "b")
        let c = await cache.value(forKey: "c")
        XCTAssertNil(a)
        XCTAssertEqual(b, 2)
        XCTAssertEqual(c, 3)
    }

    func testAccessingKeyPromotesItToMostRecentlyUsed() async {
        let cache = LRUCache<String, Int>(capacity: 2)
        await cache.setValue(1, forKey: "a")
        await cache.setValue(2, forKey: "b")
        _ = await cache.value(forKey: "a") // "a" is now MRU, "b" is LRU
        await cache.setValue(3, forKey: "c") // evicts "b"

        let a = await cache.value(forKey: "a")
        let b = await cache.value(forKey: "b")
        XCTAssertEqual(a, 1)
        XCTAssertNil(b)
    }

    func testSetValueReturnsEvictedValue() async {
        let cache = LRUCache<String, Int>(capacity: 1)
        let firstEviction = await cache.setValue(1, forKey: "a")
        let secondEviction = await cache.setValue(2, forKey: "b")
        XCTAssertNil(firstEviction)
        XCTAssertEqual(secondEviction, 1)
    }

    // MARK: - Removal

    func testRemoveValueForKey() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        await cache.setValue(1, forKey: "a")
        let removed = await cache.removeValue(forKey: "a")
        let count = await cache.count
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(count, 0)
    }

    func testRemoveAll() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        await cache.setValue(1, forKey: "a")
        await cache.setValue(2, forKey: "b")
        await cache.removeAll()
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    // MARK: - Capacity changes

    func testReducingCapacityEvictsExcessEntries() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        await cache.setValue(1, forKey: "a")
        await cache.setValue(2, forKey: "b")
        await cache.setValue(3, forKey: "c")
        await cache.setCapacity(1)

        let count = await cache.count
        let c = await cache.value(forKey: "c")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(c, 3) // most recently used survives
    }

    // MARK: - TTL / expiration

    func testEntryExpiresAfterTTL() async {
        var now = Date(timeIntervalSince1970: 0)
        let cache = LRUCache<String, Int>(capacity: 3, defaultTTL: 10, clock: { now })
        await cache.setValue(1, forKey: "a")

        now = now.addingTimeInterval(5)
        let stillThere = await cache.value(forKey: "a")
        XCTAssertEqual(stillThere, 1)

        now = now.addingTimeInterval(6) // total 11s elapsed, past the 10s TTL
        let expired = await cache.value(forKey: "a")
        XCTAssertNil(expired)
    }

    func testPerEntryTTLOverridesDefault() async {
        var now = Date(timeIntervalSince1970: 0)
        let cache = LRUCache<String, Int>(capacity: 3, defaultTTL: 100, clock: { now })
        await cache.setValue(1, forKey: "short", ttl: 1)
        await cache.setValue(2, forKey: "long")

        now = now.addingTimeInterval(2)
        let short = await cache.value(forKey: "short")
        let long = await cache.value(forKey: "long")
        XCTAssertNil(short)
        XCTAssertEqual(long, 2)
    }

    func testContainsRespectsExpiration() async {
        var now = Date(timeIntervalSince1970: 0)
        let cache = LRUCache<String, Int>(capacity: 3, defaultTTL: 5, clock: { now })
        await cache.setValue(1, forKey: "a")
        XCTAssertTrue(await cache.contains("a"))

        now = now.addingTimeInterval(6)
        XCTAssertFalse(await cache.contains("a"))
    }

    func testPurgeExpiredRemovesOnlyExpiredEntries() async {
        var now = Date(timeIntervalSince1970: 0)
        let cache = LRUCache<String, Int>(capacity: 5, clock: { now })
        await cache.setValue(1, forKey: "a", ttl: 1)
        await cache.setValue(2, forKey: "b") // no expiration

        now = now.addingTimeInterval(2)
        await cache.purgeExpired()

        let count = await cache.count
        let b = await cache.value(forKey: "b")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(b, 2)
    }

    // MARK: - allValues ordering

    func testAllValuesOrderedMostToLeastRecentlyUsed() async {
        let cache = LRUCache<String, Int>(capacity: 5)
        await cache.setValue(1, forKey: "a")
        await cache.setValue(2, forKey: "b")
        await cache.setValue(3, forKey: "c")
        _ = await cache.value(forKey: "a") // promote "a" to MRU

        let values = await cache.allValues()
        XCTAssertEqual(values, [1, 3, 2])
    }
}
