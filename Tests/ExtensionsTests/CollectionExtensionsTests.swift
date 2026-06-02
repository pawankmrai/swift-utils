import XCTest
@testable import SwiftUtilsExtensions

final class CollectionExtensionsTests: XCTestCase {

    // MARK: - isNotEmpty

    func testIsNotEmpty() {
        XCTAssertTrue([1].isNotEmpty)
        XCTAssertFalse([Int]().isNotEmpty)
    }

    // MARK: - Safe Subscript

    func testSafeSubscriptInBounds() {
        let arr = ["a", "b", "c"]
        XCTAssertEqual(arr[safe: 1], "b")
    }

    func testSafeSubscriptOutOfBounds() {
        let arr = [1, 2]
        XCTAssertNil(arr[safe: 5])
        XCTAssertNil(arr[safe: -1])
    }

    func testSafeSubscriptOnSlice() {
        let slice: ArraySlice = ["x", "y", "z"][1...]
        XCTAssertEqual(slice[safe: 2], "z")
        XCTAssertNil(slice[safe: 0]) // 0 is not in the slice's indices
    }

    // MARK: - nilIfEmpty

    func testNilIfEmptyOnEmpty() {
        let empty: [String] = []
        XCTAssertNil(empty.nilIfEmpty)
    }

    func testNilIfEmptyOnNonEmpty() {
        XCTAssertNotNil([1, 2].nilIfEmpty)
    }

    // MARK: - onlyElement

    func testOnlyElementSingle() {
        XCTAssertEqual([42].onlyElement, 42)
    }

    func testOnlyElementMultiple() {
        XCTAssertNil([1, 2].onlyElement)
    }

    func testOnlyElementEmpty() {
        XCTAssertNil([Int]().onlyElement)
    }

    // MARK: - Partitioned

    func testPartitioned() {
        let (evens, odds) = [1, 2, 3, 4, 5].partitioned { $0.isMultiple(of: 2) }
        XCTAssertEqual(evens, [2, 4])
        XCTAssertEqual(odds, [1, 3, 5])
    }

    func testPartitionedEmpty() {
        let (matching, nonMatching) = [Int]().partitioned { $0 > 0 }
        XCTAssertTrue(matching.isEmpty)
        XCTAssertTrue(nonMatching.isEmpty)
    }

    // MARK: - Sum

    func testSumIntegers() {
        XCTAssertEqual([1, 2, 3, 4].sum(), 10)
    }

    func testSumFloats() {
        XCTAssertEqual([1.5, 2.5].sum(), 4.0)
    }

    func testSumEmpty() {
        XCTAssertEqual([Int]().sum(), 0)
    }

    // MARK: - Average

    func testAverageIntegers() {
        XCTAssertEqual([2, 4, 6].average(), 4.0)
    }

    func testAverageFloats() {
        let avg: Double? = [1.0, 2.0, 3.0].average()
        XCTAssertEqual(avg, 2.0)
    }

    func testAverageEmpty() {
        XCTAssertNil([Int]().average())
        XCTAssertNil([Double]().average())
    }

    // MARK: - Key-Path Sum & Average

    struct Item {
        let price: Double
    }

    func testSumOfKeyPath() {
        let items = [Item(price: 10.0), Item(price: 20.0)]
        XCTAssertEqual(items.sum(of: \.price), 30.0)
    }

    func testAverageOfKeyPath() {
        let items = [Item(price: 10.0), Item(price: 30.0)]
        XCTAssertEqual(items.average(of: \.price), 20.0)
    }

    func testAverageOfKeyPathEmpty() {
        let items: [Item] = []
        XCTAssertNil(items.average(of: \.price))
    }

    // MARK: - keyed(by:)

    struct User {
        let id: Int
        let name: String
    }

    func testKeyedBy() {
        let users = [User(id: 1, name: "A"), User(id: 2, name: "B")]
        let dict = users.keyed(by: \.id)
        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(dict[1]?.name, "A")
        XCTAssertEqual(dict[2]?.name, "B")
    }

    func testKeyedByDuplicatesKeepsLast() {
        let users = [User(id: 1, name: "First"), User(id: 1, name: "Last")]
        let dict = users.keyed(by: \.id)
        XCTAssertEqual(dict[1]?.name, "Last")
    }

    // MARK: - allEqual

    func testAllEqualTrue() {
        XCTAssertTrue([5, 5, 5].allEqual())
    }

    func testAllEqualFalse() {
        XCTAssertFalse([1, 2, 3].allEqual())
    }

    func testAllEqualEmpty() {
        XCTAssertTrue([Int]().allEqual())
    }

    // MARK: - count(of:)

    func testCountOf() {
        XCTAssertEqual([1, 2, 1, 3, 1].count(of: 1), 3)
        XCTAssertEqual([1, 2, 3].count(of: 9), 0)
    }

    // MARK: - indices(where:)

    func testIndicesWhere() {
        let result = [10, 20, 30, 40, 50].indices(where: { $0 > 25 })
        XCTAssertEqual(result, [2, 3, 4])
    }

    func testIndicesWhereNone() {
        let result = [1, 2, 3].indices(where: { $0 > 10 })
        XCTAssertTrue(result.isEmpty)
    }
}
