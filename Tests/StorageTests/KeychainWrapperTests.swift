import XCTest
@testable import SwiftUtilsStorage

final class KeychainWrapperTests: XCTestCase {

    private var keychain: KeychainWrapper!
    private let testService = "com.swiftutils.tests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        keychain = KeychainWrapper(service: testService)
    }

    override func tearDown() {
        try? keychain.removeAll()
        keychain = nil
        super.tearDown()
    }

    // MARK: - String Tests

    func testSetAndGetString() throws {
        try keychain.set("hello-world", forKey: "token")
        let result = try keychain.string(forKey: "token")
        XCTAssertEqual(result, "hello-world")
    }

    func testGetStringReturnsNilForMissingKey() throws {
        let result = try keychain.string(forKey: "nonexistent")
        XCTAssertNil(result)
    }

    func testOverwriteExistingString() throws {
        try keychain.set("first", forKey: "key")
        try keychain.set("second", forKey: "key")
        let result = try keychain.string(forKey: "key")
        XCTAssertEqual(result, "second")
    }

    func testStoreAndRetrieveEmptyString() throws {
        try keychain.set("", forKey: "emptyKey")
        let result = try keychain.string(forKey: "emptyKey")
        XCTAssertEqual(result, "")
    }

    func testStoreUnicodeString() throws {
        let value = "こんにちは世界 🌍🎉"
        try keychain.set(value, forKey: "unicode")
        let result = try keychain.string(forKey: "unicode")
        XCTAssertEqual(result, value)
    }

    // MARK: - Data Tests

    func testSetAndGetData() throws {
        let data = Data([0x01, 0x02, 0x03, 0xFF])
        try keychain.setData(data, forKey: "rawData")
        let result = try keychain.data(forKey: "rawData")
        XCTAssertEqual(result, data)
    }

    // MARK: - Codable Tests

    private struct Credentials: Codable, Equatable {
        let username: String
        let apiKey: String
        let expiresIn: Int
    }

    func testSetAndGetCodable() throws {
        let creds = Credentials(username: "pawan", apiKey: "sk-12345", expiresIn: 3600)
        try keychain.setCodable(creds, forKey: "credentials")
        let result: Credentials? = try keychain.codable(forKey: "credentials")
        XCTAssertEqual(result, creds)
    }

    func testGetCodableReturnsNilForMissingKey() throws {
        let result: Credentials? = try keychain.codable(forKey: "missing")
        XCTAssertNil(result)
    }

    // MARK: - Removal Tests

    func testRemoveExistingItem() throws {
        try keychain.set("toRemove", forKey: "tempKey")
        let removed = try keychain.remove(forKey: "tempKey")
        XCTAssertTrue(removed)
        let result = try keychain.string(forKey: "tempKey")
        XCTAssertNil(result)
    }

    func testRemoveNonexistentItemReturnsFalse() throws {
        let removed = try keychain.remove(forKey: "neverStored")
        XCTAssertFalse(removed)
    }

    func testRemoveAll() throws {
        try keychain.set("a", forKey: "key1")
        try keychain.set("b", forKey: "key2")
        try keychain.set("c", forKey: "key3")
        try keychain.removeAll()
        XCTAssertNil(try keychain.string(forKey: "key1"))
        XCTAssertNil(try keychain.string(forKey: "key2"))
        XCTAssertNil(try keychain.string(forKey: "key3"))
    }

    // MARK: - Contains Tests

    func testContainsReturnsTrueForExistingKey() throws {
        try keychain.set("value", forKey: "existingKey")
        XCTAssertTrue(try keychain.contains("existingKey"))
    }

    func testContainsReturnsFalseForMissingKey() throws {
        XCTAssertFalse(try keychain.contains("missingKey"))
    }

    // MARK: - Service Isolation Tests

    func testDifferentServicesAreIsolated() throws {
        let otherKeychain = KeychainWrapper(service: "com.other.\(UUID().uuidString)")
        defer { try? otherKeychain.removeAll() }

        try keychain.set("original", forKey: "sharedKey")
        try otherKeychain.set("different", forKey: "sharedKey")

        XCTAssertEqual(try keychain.string(forKey: "sharedKey"), "original")
        XCTAssertEqual(try otherKeychain.string(forKey: "sharedKey"), "different")
    }

    // MARK: - Accessibility Tests

    func testCustomAccessibility() throws {
        let secureKeychain = KeychainWrapper(
            service: testService + ".secure",
            accessibility: .afterFirstUnlock
        )
        defer { try? secureKeychain.removeAll() }

        try secureKeychain.set("persistent-token", forKey: "bgToken")
        let result = try secureKeychain.string(forKey: "bgToken")
        XCTAssertEqual(result, "persistent-token")
    }

    // MARK: - KeychainError Tests

    func testErrorDescriptions() {
        XCTAssertNotNil(KeychainError.itemNotFound.errorDescription)
        XCTAssertNotNil(KeychainError.duplicateItem.errorDescription)
        XCTAssertNotNil(KeychainError.unexpectedStatus(-25300).errorDescription)
        XCTAssertNotNil(KeychainError.encodingFailed.errorDescription)
        XCTAssertNotNil(KeychainError.decodingFailed.errorDescription)
    }

    func testErrorEquality() {
        XCTAssertEqual(KeychainError.itemNotFound, KeychainError.itemNotFound)
        XCTAssertEqual(KeychainError.unexpectedStatus(-1), KeychainError.unexpectedStatus(-1))
        XCTAssertNotEqual(KeychainError.itemNotFound, KeychainError.duplicateItem)
    }
}
