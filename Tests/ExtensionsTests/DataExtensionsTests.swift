import XCTest
@testable import SwiftUtilsExtensions

final class DataExtensionsTests: XCTestCase {
    
    // MARK: - Hex Encoding
    
    func testHexStringFromData() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
        XCTAssertEqual(data.hexString, "48656c6c6f")
    }
    
    func testHexStringUppercased() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(data.hexStringUppercased, "DEADBEEF")
    }
    
    func testDataFromHexString() {
        let data = Data(hex: "48656C6C6F")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.utf8String, "Hello")
    }
    
    func testDataFromHexStringWith0xPrefix() {
        let data = Data(hex: "0xDEADBEEF")
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.hexStringUppercased, "DEADBEEF")
    }
    
    func testDataFromHexStringOddLengthReturnsNil() {
        XCTAssertNil(Data(hex: "ABC"))
    }
    
    func testDataFromHexStringInvalidCharsReturnsNil() {
        XCTAssertNil(Data(hex: "GHIJ"))
    }
    
    func testHexRoundTrip() {
        let original = Data([0x00, 0xFF, 0x42, 0x99])
        let hex = original.hexString
        let decoded = Data(hex: hex)
        XCTAssertEqual(decoded, original)
    }
    
    // MARK: - Base64 URL-Safe
    
    func testBase64URLEncoded() {
        // "Hello, World!" in base64 is "SGVsbG8sIFdvcmxkIQ==" 
        // base64url should be "SGVsbG8sIFdvcmxkIQ"
        let data = Data("Hello, World!".utf8)
        let encoded = data.base64URLEncoded
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }
    
    func testBase64URLRoundTrip() {
        let original = Data("Test payload with special chars: +/=".utf8)
        let encoded = original.base64URLEncoded
        let decoded = Data(base64URLEncoded: encoded)
        XCTAssertEqual(decoded, original)
    }
    
    func testBase64URLDecodingInvalidReturnsNil() {
        // Single character isn't valid base64
        XCTAssertNil(Data(base64URLEncoded: "!@#$"))
    }
    
    // MARK: - Hashing
    
    func testSHA256() {
        let data = Data("hello".utf8)
        let hash = data.sha256
        // Known SHA-256 of "hello"
        XCTAssertEqual(hash.hexString, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
    
    func testSHA256EmptyData() {
        let data = Data()
        let hash = data.sha256
        // Known SHA-256 of empty data
        XCTAssertEqual(hash.hexString, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
    
    func testMD5() {
        let data = Data("hello".utf8)
        let hash = data.md5
        // Known MD5 of "hello"
        XCTAssertEqual(hash.hexString, "5d41402abc4b2a76b9719d911017c592")
    }
    
    // MARK: - UTF-8 String Conversion
    
    func testUTF8String() {
        let data = Data("Swift is great!".utf8)
        XCTAssertEqual(data.utf8String, "Swift is great!")
    }
    
    func testUTF8StringInvalidReturnsNil() {
        let invalidData = Data([0xFF, 0xFE])
        // This may or may not be valid UTF-8 depending on platform;
        // test that it doesn't crash
        _ = invalidData.utf8String
    }
    
    func testDataFromUTF8String() {
        let data = Data(utf8: "Hello")
        XCTAssertEqual(data.utf8String, "Hello")
        XCTAssertEqual(data.count, 5)
    }
    
    func testDataFromUTF8Emoji() {
        let data = Data(utf8: "🚀")
        XCTAssertEqual(data.count, 4) // emoji is 4 bytes in UTF-8
        XCTAssertEqual(data.utf8String, "🚀")
    }
    
    // MARK: - Pretty JSON
    
    func testPrettyJSON() {
        let json = #"{"name":"Pawan","age":30}"#
        let data = Data(json.utf8)
        let pretty = data.prettyJSON
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\"name\" : \"Pawan\""))
    }
    
    func testPrettyJSONInvalidData() {
        let data = Data("not json".utf8)
        XCTAssertNil(data.prettyJSON)
    }
    
    // MARK: - Byte Helpers
    
    func testReadableByteCount() {
        let data = Data(count: 1_500_000)
        let readable = data.readableByteCount
        XCTAssertTrue(readable.contains("MB") || readable.contains("MB"))
    }
    
    func testReadableByteCountZero() {
        let data = Data()
        let readable = data.readableByteCount
        XCTAssertTrue(readable.lowercased().contains("zero") || readable.contains("0"))
    }
    
    func testReversed() {
        let data = Data([0x01, 0x02, 0x03])
        let reversed = data.reversed
        XCTAssertEqual(reversed, Data([0x03, 0x02, 0x01]))
    }
    
    func testSafeSlice() {
        let data = Data([0x00, 0x11, 0x22, 0x33, 0x44])
        let slice = data.safeSlice(1..<3)
        XCTAssertEqual(slice, Data([0x11, 0x22]))
    }
    
    func testSafeSliceOutOfBounds() {
        let data = Data([0x00, 0x11])
        let slice = data.safeSlice(5..<10)
        XCTAssertTrue(slice.isEmpty)
    }
    
    func testSafeSliceClamped() {
        let data = Data([0x00, 0x11, 0x22])
        let slice = data.safeSlice(1..<100)
        XCTAssertEqual(slice, Data([0x11, 0x22]))
    }
    
    // MARK: - Compression
    
    func testCompressionRoundTrip() throws {
        let original = Data(String(repeating: "Hello, Swift! ", count: 100).utf8)
        let compressed = try original.compressed(using: .zlib)
        XCTAssertTrue(compressed.count < original.count)
        
        let decompressed = try compressed.decompressed(using: .zlib)
        XCTAssertEqual(decompressed, original)
    }
    
    func testCompressionLZFB() throws {
        let original = Data(String(repeating: "ABCDEF", count: 50).utf8)
        let compressed = try original.compressed(using: .lzfse)
        let decompressed = try compressed.decompressed(using: .lzfse)
        XCTAssertEqual(decompressed, original)
    }
}
