import XCTest
@testable import SwiftUtilsStorage

final class UserDefaultsWrapperTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: #file)!
        suite.removePersistentDomain(forName: #file)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: #file)
        suite = nil
        super.tearDown()
    }

    // MARK: - UserDefault (non-optional)

    func testBoolDefaultValue() {
        var wrapper = UserDefault<Bool>("test_bool", defaultValue: false, suite: suite)
        XCTAssertFalse(wrapper.wrappedValue)
    }

    func testBoolSetAndGet() {
        var wrapper = UserDefault<Bool>("test_bool", defaultValue: false, suite: suite)
        wrapper.wrappedValue = true
        XCTAssertTrue(wrapper.wrappedValue)
    }

    func testIntDefaultValue() {
        var wrapper = UserDefault<Int>("test_int", defaultValue: 42, suite: suite)
        XCTAssertEqual(wrapper.wrappedValue, 42)
    }

    func testIntSetAndGet() {
        var wrapper = UserDefault<Int>("test_int", defaultValue: 0, suite: suite)
        wrapper.wrappedValue = 99
        XCTAssertEqual(wrapper.wrappedValue, 99)
    }

    func testStringDefaultValue() {
        var wrapper = UserDefault<String>("test_string", defaultValue: "hello", suite: suite)
        XCTAssertEqual(wrapper.wrappedValue, "hello")
    }

    func testStringSetAndGet() {
        var wrapper = UserDefault<String>("test_string", defaultValue: "", suite: suite)
        wrapper.wrappedValue = "world"
        XCTAssertEqual(wrapper.wrappedValue, "world")
    }

    func testDoubleSetAndGet() {
        var wrapper = UserDefault<Double>("test_double", defaultValue: 0.0, suite: suite)
        wrapper.wrappedValue = 3.14
        XCTAssertEqual(wrapper.wrappedValue, 3.14, accuracy: 0.001)
    }

    func testRemove() {
        var wrapper = UserDefault<String>("test_remove", defaultValue: "default", suite: suite)
        wrapper.wrappedValue = "changed"
        XCTAssertEqual(wrapper.wrappedValue, "changed")

        wrapper.remove()
        XCTAssertEqual(wrapper.wrappedValue, "default")
    }

    func testIsSet() {
        var wrapper = UserDefault<Int>("test_isset", defaultValue: 0, suite: suite)
        XCTAssertFalse(wrapper.isSet)

        wrapper.wrappedValue = 10
        XCTAssertTrue(wrapper.isSet)

        wrapper.remove()
        XCTAssertFalse(wrapper.isSet)
    }

    // MARK: - OptionalUserDefault

    func testOptionalDefaultIsNil() {
        var wrapper = OptionalUserDefault<String>("test_optional", suite: suite)
        XCTAssertNil(wrapper.wrappedValue)
    }

    func testOptionalSetAndGet() {
        var wrapper = OptionalUserDefault<String>("test_optional", suite: suite)
        wrapper.wrappedValue = "value"
        XCTAssertEqual(wrapper.wrappedValue, "value")
    }

    func testOptionalSetToNilRemoves() {
        var wrapper = OptionalUserDefault<String>("test_optional_nil", suite: suite)
        wrapper.wrappedValue = "temp"
        XCTAssertTrue(wrapper.isSet)

        wrapper.wrappedValue = nil
        XCTAssertFalse(wrapper.isSet)
        XCTAssertNil(wrapper.wrappedValue)
    }

    // MARK: - URL Support

    func testURLSetAndGet() {
        var wrapper = OptionalUserDefault<URL>("test_url", suite: suite)
        let url = URL(string: "https://example.com")!
        wrapper.wrappedValue = url
        XCTAssertEqual(wrapper.wrappedValue, url)
    }

    // MARK: - Data Support

    func testDataSetAndGet() {
        var wrapper = UserDefault<Data>("test_data", defaultValue: Data(), suite: suite)
        let data = "hello".data(using: .utf8)!
        wrapper.wrappedValue = data
        XCTAssertEqual(wrapper.wrappedValue, data)
    }

    // MARK: - Array Support

    func testStringArraySetAndGet() {
        var wrapper = UserDefault<[String]>("test_array", defaultValue: [], suite: suite)
        wrapper.wrappedValue = ["a", "b", "c"]
        XCTAssertEqual(wrapper.wrappedValue, ["a", "b", "c"])
    }

    // MARK: - CodableUserDefault

    func testCodableDefaultValue() {
        struct Point: Codable, Equatable { var x: Int; var y: Int }
        var wrapper = CodableUserDefault<Point>("test_codable", defaultValue: Point(x: 0, y: 0), suite: suite)
        XCTAssertEqual(wrapper.wrappedValue, Point(x: 0, y: 0))
    }

    func testCodableSetAndGet() {
        struct Point: Codable, Equatable { var x: Int; var y: Int }
        var wrapper = CodableUserDefault<Point>("test_codable2", defaultValue: Point(x: 0, y: 0), suite: suite)
        wrapper.wrappedValue = Point(x: 5, y: 10)
        XCTAssertEqual(wrapper.wrappedValue, Point(x: 5, y: 10))
    }

    func testCodableRemove() {
        struct Point: Codable, Equatable { var x: Int; var y: Int }
        var wrapper = CodableUserDefault<Point>("test_codable3", defaultValue: Point(x: 0, y: 0), suite: suite)
        wrapper.wrappedValue = Point(x: 5, y: 10)
        wrapper.remove()
        XCTAssertEqual(wrapper.wrappedValue, Point(x: 0, y: 0))
    }
}
