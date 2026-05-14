//
//  ArrayExtensionsTests.swift
//  SwiftUtils
//

import XCTest
@testable import SwiftUtilsExtensions

final class ArrayExtensionsTests: XCTestCase {

    // MARK: - Safe Subscript

    func testSafeSubscriptReturnsElement() {
        let array = ["a", "b", "c"]
        XCTAssertEqual(array[safe: 0], "a")
        XCTAssertEqual(array[safe: 2], "c")
    }

    func testSafeSubscriptReturnsNilForOutOfBounds() {
        let array = [1, 2, 3]
        XCTAssertNil(array[safe: 3])
        XCTAssertNil(array[safe: -1])
        XCTAssertNil(array[safe: 100])
    }

    func testSafeSubscriptOnEmptyArray() {
        let array: [Int] = []
        XCTAssertNil(array[safe: 0])
    }

    // MARK: - Chunked

    func testChunkedEvenlyDivisible() {
        let result = [1, 2, 3, 4].chunked(into: 2)
        XCTAssertEqual(result, [[1, 2], [3, 4]])
    }

    func testChunkedWithRemainder() {
        let result = [1, 2, 3, 4, 5].chunked(into: 2)
        XCTAssertEqual(result, [[1, 2], [3, 4], [5]])
    }

    func testChunkedSingleElementChunks() {
        let result = [1, 2, 3].chunked(into: 1)
        XCTAssertEqual(result, [[1], [2], [3]])
    }

    func testChunkedLargerThanArray() {
        let result = [1, 2].chunked(into: 10)
        XCTAssertEqual(result, [[1, 2]])
    }

    func testChunkedEmptyArray() {
        let result: [[Int]] = [Int]().chunked(into: 3)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Uniqued (Equatable)

    func testUniquedRemovesDuplicates() {
        XCTAssertEqual([1, 2, 3, 2, 1, 4].uniqued(), [1, 2, 3, 4])
    }

    func testUniquedPreservesOrder() {
        XCTAssertEqual(["b", "a", "b", "c", "a"].uniqued(), ["b", "a", "c"])
    }

    func testUniquedNoDuplicates() {
        XCTAssertEqual([1, 2, 3].uniqued(), [1, 2, 3])
    }

    func testUniquedEmptyArray() {
        XCTAssertEqual([Int]().uniqued(), [])
    }

    // MARK: - Uniqued Fast (Hashable)

    func testUniquedFastRemovesDuplicates() {
        XCTAssertEqual([1, 2, 3, 2, 1, 4].uniquedFast(), [1, 2, 3, 4])
    }

    func testUniquedFastPreservesOrder() {
        XCTAssertEqual(["b", "a", "b", "c", "a"].uniquedFast(), ["b", "a", "c"])
    }

    // MARK: - Uniqued by Key Path

    func testUniquedByKeyPath() {
        struct Item: Equatable {
            let id: Int
            let name: String
        }
        let items = [Item(id: 1, name: "A"), Item(id: 2, name: "B"), Item(id: 1, name: "C")]
        let result = items.uniqued(by: \.id)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "A")
        XCTAssertEqual(result[1].name, "B")
    }

    // MARK: - Grouped

    func testGroupedByKeyPath() {
        struct Task {
            let priority: String
            let title: String
        }
        let tasks = [
            Task(priority: "high", title: "Fix crash"),
            Task(priority: "low", title: "Update docs"),
            Task(priority: "high", title: "Ship feature"),
        ]
        let grouped = tasks.grouped(by: \.priority)
        XCTAssertEqual(grouped["high"]?.count, 2)
        XCTAssertEqual(grouped["low"]?.count, 1)
        XCTAssertNil(grouped["medium"])
    }

    // MARK: - Frequencies

    func testFrequencies() {
        let freq = ["a", "b", "a", "c", "a", "b"].frequencies()
        XCTAssertEqual(freq["a"], 3)
        XCTAssertEqual(freq["b"], 2)
        XCTAssertEqual(freq["c"], 1)
    }

    func testFrequenciesEmpty() {
        let freq = [String]().frequencies()
        XCTAssertTrue(freq.isEmpty)
    }

    // MARK: - Min / Max by Key Path

    func testMinByKeyPath() {
        struct Product {
            let name: String
            let price: Double
        }
        let products = [
            Product(name: "Expensive", price: 99.99),
            Product(name: "Cheap", price: 9.99),
            Product(name: "Mid", price: 49.99),
        ]
        let cheapest = products.min(by: \.price)
        XCTAssertEqual(cheapest?.name, "Cheap")
    }

    func testMaxByKeyPath() {
        let result = [3, 1, 4, 1, 5, 9].max(by: \.self)
        XCTAssertEqual(result, 9)
    }

    func testMinByKeyPathEmptySequence() {
        let empty: [Int] = []
        XCTAssertNil(empty.min(by: \.self))
    }

    // MARK: - Sorted by Key Path

    func testSortedByKeyPathAscending() {
        struct User {
            let name: String
            let age: Int
        }
        let users = [User(name: "B", age: 30), User(name: "A", age: 25), User(name: "C", age: 35)]
        let sorted = users.sorted(by: \.age)
        XCTAssertEqual(sorted.map(\.age), [25, 30, 35])
    }

    func testSortedByKeyPathDescending() {
        let sorted = [1, 3, 2, 5, 4].sorted(by: \.self, ascending: false)
        XCTAssertEqual(sorted, [5, 4, 3, 2, 1])
    }

    // MARK: - Compact Map Unwrapping

    func testCompactMapUnwrapping() {
        struct Contact {
            let email: String?
        }
        let contacts = [
            Contact(email: "a@b.com"),
            Contact(email: nil),
            Contact(email: "c@d.com"),
        ]
        let emails = contacts.compactMap(unwrapping: \.email)
        XCTAssertEqual(emails, ["a@b.com", "c@d.com"])
    }

    // MARK: - Append If Absent

    func testAppendIfAbsentAddsNewElement() {
        var array = ["swift", "ios"]
        let added = array.appendIfAbsent("macOS")
        XCTAssertTrue(added)
        XCTAssertEqual(array, ["swift", "ios", "macOS"])
    }

    func testAppendIfAbsentSkipsExistingElement() {
        var array = ["swift", "ios"]
        let added = array.appendIfAbsent("swift")
        XCTAssertFalse(added)
        XCTAssertEqual(array, ["swift", "ios"])
    }

    func testAppendIfAbsentOnEmptyArray() {
        var array: [Int] = []
        let added = array.appendIfAbsent(1)
        XCTAssertTrue(added)
        XCTAssertEqual(array, [1])
    }
}
