import XCTest
@testable import SwiftUtilsExtensions

final class OptionalExtensionsTests: XCTestCase {
    
    // MARK: - orThrow
    
    struct TestError: Error, Equatable {
        let message: String
    }
    
    func testOrThrowReturnsValueWhenPresent() throws {
        let optional: String? = "hello"
        let result = try optional.orThrow(TestError(message: "missing"))
        XCTAssertEqual(result, "hello")
    }
    
    func testOrThrowThrowsWhenNil() {
        let optional: String? = nil
        XCTAssertThrowsError(try optional.orThrow(TestError(message: "missing"))) { error in
            XCTAssertEqual(error as? TestError, TestError(message: "missing"))
        }
    }
    
    // MARK: - or
    
    func testOrReturnsValueWhenPresent() {
        let optional: Int? = 42
        XCTAssertEqual(optional.or(0), 42)
    }
    
    func testOrReturnsDefaultWhenNil() {
        let optional: Int? = nil
        XCTAssertEqual(optional.or(99), 99)
    }
    
    // MARK: - ifLet / ifNil
    
    func testIfLetExecutesWhenPresent() {
        let optional: String? = "test"
        var executed = false
        optional.ifLet { _ in executed = true }
        XCTAssertTrue(executed)
    }
    
    func testIfLetDoesNotExecuteWhenNil() {
        let optional: String? = nil
        var executed = false
        optional.ifLet { _ in executed = true }
        XCTAssertFalse(executed)
    }
    
    func testIfNilExecutesWhenNil() {
        let optional: String? = nil
        var executed = false
        optional.ifNil { executed = true }
        XCTAssertTrue(executed)
    }
    
    func testIfNilDoesNotExecuteWhenPresent() {
        let optional: String? = "value"
        var executed = false
        optional.ifNil { executed = true }
        XCTAssertFalse(executed)
    }
    
    // MARK: - isNil / isNotNil
    
    func testIsNil() {
        let nilOptional: Int? = nil
        let someOptional: Int? = 5
        XCTAssertTrue(nilOptional.isNil)
        XCTAssertFalse(someOptional.isNil)
    }
    
    func testIsNotNil() {
        let nilOptional: Int? = nil
        let someOptional: Int? = 5
        XCTAssertFalse(nilOptional.isNotNil)
        XCTAssertTrue(someOptional.isNotNil)
    }
    
    // MARK: - filter
    
    func testFilterReturnsValueWhenPredicateMatches() {
        let optional: Int? = 25
        XCTAssertEqual(optional.filter { $0 >= 18 }, 25)
    }
    
    func testFilterReturnsNilWhenPredicateFails() {
        let optional: Int? = 10
        XCTAssertNil(optional.filter { $0 >= 18 })
    }
    
    func testFilterReturnsNilWhenOptionalIsNil() {
        let optional: Int? = nil
        XCTAssertNil(optional.filter { $0 >= 18 })
    }
    
    // MARK: - zip
    
    func testZipReturnsTupleWhenBothPresent() {
        let a: String? = "name"
        let b: Int? = 30
        let result = a.zip(b)
        XCTAssertEqual(result?.0, "name")
        XCTAssertEqual(result?.1, 30)
    }
    
    func testZipReturnsNilWhenFirstIsNil() {
        let a: String? = nil
        let b: Int? = 30
        XCTAssertNil(a.zip(b))
    }
    
    func testZipReturnsNilWhenSecondIsNil() {
        let a: String? = "name"
        let b: Int? = nil
        XCTAssertNil(a.zip(b))
    }
    
    func testZipThreeReturnsTupleWhenAllPresent() {
        let a: String? = "x"
        let b: Int? = 1
        let c: Double? = 3.14
        let result = a.zip(b, c)
        XCTAssertEqual(result?.0, "x")
        XCTAssertEqual(result?.1, 1)
        XCTAssertEqual(result?.2, 3.14)
    }
    
    func testZipThreeReturnsNilWhenAnyIsNil() {
        let a: String? = "x"
        let b: Int? = nil
        let c: Double? = 3.14
        XCTAssertNil(a.zip(b, c))
    }
    
    // MARK: - Collection extensions
    
    func testIsNilOrEmptyWithNil() {
        let array: [Int]? = nil
        XCTAssertTrue(array.isNilOrEmpty)
    }
    
    func testIsNilOrEmptyWithEmpty() {
        let array: [Int]? = []
        XCTAssertTrue(array.isNilOrEmpty)
    }
    
    func testIsNilOrEmptyWithValues() {
        let array: [Int]? = [1, 2, 3]
        XCTAssertFalse(array.isNilOrEmpty)
    }
    
    func testNilIfEmptyReturnsNilForEmpty() {
        let array: [String]? = []
        XCTAssertNil(array.nilIfEmpty)
    }
    
    func testNilIfEmptyReturnsCollectionForNonEmpty() {
        let array: [String]? = ["hello"]
        XCTAssertEqual(array.nilIfEmpty, ["hello"])
    }
    
    // MARK: - String extensions
    
    func testIsNilOrBlankWithNil() {
        let str: String? = nil
        XCTAssertTrue(str.isNilOrBlank)
    }
    
    func testIsNilOrBlankWithWhitespace() {
        let str: String? = "   \n\t  "
        XCTAssertTrue(str.isNilOrBlank)
    }
    
    func testIsNilOrBlankWithContent() {
        let str: String? = "hello"
        XCTAssertFalse(str.isNilOrBlank)
    }
    
    func testNilIfBlankReturnsNilForBlank() {
        let str: String? = "   "
        XCTAssertNil(str.nilIfBlank)
    }
    
    func testNilIfBlankReturnsStringForContent() {
        let str: String? = "hello"
        XCTAssertEqual(str.nilIfBlank, "hello")
    }
    
    func testOrEmptyReturnsStringWhenPresent() {
        let str: String? = "test"
        XCTAssertEqual(str.orEmpty, "test")
    }
    
    func testOrEmptyReturnsEmptyWhenNil() {
        let str: String? = nil
        XCTAssertEqual(str.orEmpty, "")
    }
    
    // MARK: - Numeric extensions
    
    func testOrZeroReturnsValueWhenPresent() {
        let num: Int? = 42
        XCTAssertEqual(num.orZero, 42)
    }
    
    func testOrZeroReturnsZeroWhenNil() {
        let num: Double? = nil
        XCTAssertEqual(num.orZero, 0.0)
    }
    
    // MARK: - Bool extensions
    
    func testOrFalseReturnsFalseWhenNil() {
        let flag: Bool? = nil
        XCTAssertFalse(flag.orFalse)
    }
    
    func testOrFalseReturnsValueWhenPresent() {
        let flag: Bool? = true
        XCTAssertTrue(flag.orFalse)
    }
    
    func testOrTrueReturnsTrueWhenNil() {
        let flag: Bool? = nil
        XCTAssertTrue(flag.orTrue)
    }
    
    func testOrTrueReturnsValueWhenPresent() {
        let flag: Bool? = false
        XCTAssertFalse(flag.orTrue)
    }
}
