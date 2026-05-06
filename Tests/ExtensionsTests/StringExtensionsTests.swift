import XCTest
@testable import SwiftUtilsExtensions

final class StringExtensionsTests: XCTestCase {
    
    func testIsValidEmail() {
        XCTAssertTrue("user@example.com".isValidEmail)
        XCTAssertFalse("not-an-email".isValidEmail)
        XCTAssertFalse("".isValidEmail)
    }
    
    func testTrimmed() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("\n test \n".trimmed, "test")
    }
    
    func testIsNumeric() {
        XCTAssertTrue("12345".isNumeric)
        XCTAssertFalse("123abc".isNumeric)
        XCTAssertFalse("".isNumeric)
    }
    
    func testTruncated() {
        XCTAssertEqual("Hello World".truncated(to: 5), "Hello…")
        XCTAssertEqual("Hi".truncated(to: 5), "Hi")
    }
    
    func testSlugified() {
        XCTAssertEqual("Hello World".slugified, "hello-world")
        XCTAssertEqual("Swift is Great!".slugified, "swift-is-great")
    }
    
    func testSnakeCased() {
        XCTAssertEqual("camelCase".snakeCased, "camel_case")
        XCTAssertEqual("myVariableName".snakeCased, "my_variable_name")
    }
}
