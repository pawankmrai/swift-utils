import XCTest
@testable import SwiftUtilsExtensions

final class URLExtensionsTests: XCTestCase {

    // MARK: - Query Parameter

    func testQueryParameter() {
        let url = URL(string: "https://example.com?page=2&lang=en")!
        XCTAssertEqual(url.queryParameter("page"), "2")
        XCTAssertEqual(url.queryParameter("lang"), "en")
        XCTAssertNil(url.queryParameter("missing"))
    }

    func testAppendingQueryParameters() {
        let url = URL(string: "https://example.com?existing=1")!
        let result = url.appendingQueryParameters(["new": "2"])
        XCTAssertEqual(result?.queryParameter("existing"), "1")
        XCTAssertEqual(result?.queryParameter("new"), "2")
    }

    func testRemovingQueryParameter() {
        let url = URL(string: "https://example.com?a=1&b=2")!
        let result = url.removingQueryParameter("a")
        XCTAssertNil(result?.queryParameter("a"))
        XCTAssertEqual(result?.queryParameter("b"), "2")
    }

    func testRemovingLastQueryParameterCleansUp() {
        let url = URL(string: "https://example.com?a=1")!
        let result = url.removingQueryParameter("a")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.absoluteString.contains("?"))
    }

    func testQueryDictionary() {
        let url = URL(string: "https://example.com?x=1&y=2&z=3")!
        XCTAssertEqual(url.queryDictionary, ["x": "1", "y": "2", "z": "3"])
    }

    func testQueryDictionaryEmpty() {
        let url = URL(string: "https://example.com")!
        XCTAssertTrue(url.queryDictionary.isEmpty)
    }

    // MARK: - Path Helpers

    func testFileName() {
        let url = URL(string: "https://cdn.example.com/images/photo.jpg")!
        XCTAssertEqual(url.fileName, "photo")
    }

    func testAppendingPathComponents() {
        let base = URL(string: "https://api.example.com/v2")!
        let result = base.appendingPathComponents(["users", "123", "posts"])
        XCTAssertTrue(result.absoluteString.hasSuffix("/users/123/posts"))
    }

    // MARK: - Validation

    func testIsSecure() {
        XCTAssertTrue(URL(string: "https://example.com")!.isSecure)
        XCTAssertTrue(URL(string: "wss://example.com")!.isSecure)
        XCTAssertFalse(URL(string: "http://example.com")!.isSecure)
    }

    func testHasFileExtension() {
        let url = URL(string: "https://cdn.example.com/doc.PDF")!
        XCTAssertTrue(url.hasFileExtension(in: ["pdf", "doc"]))
        XCTAssertFalse(url.hasFileExtension(in: ["jpg"]))
    }

    func testIsImageURL() {
        XCTAssertTrue(URL(string: "https://img.com/photo.jpg")!.isImageURL)
        XCTAssertTrue(URL(string: "https://img.com/photo.WEBP")!.isImageURL)
        XCTAssertFalse(URL(string: "https://img.com/file.zip")!.isImageURL)
    }

    // MARK: - Deep Link

    func testPathSegments() {
        let url = URL(string: "myapp://settings/notifications/email")!
        XCTAssertEqual(url.pathSegments, ["settings", "notifications", "email"])
    }

    func testDeepLinkCreation() {
        let url = URL.deepLink(scheme: "myapp", host: "product", path: "/123", query: ["ref": "home"])
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "myapp")
        XCTAssertEqual(url?.host, "product")
        XCTAssertTrue(url?.path.contains("123") ?? false)
        XCTAssertEqual(url?.queryParameter("ref"), "home")
    }

    // MARK: - Masking

    func testMasked() {
        let url = URL(string: "https://api.com/search?token=secret&q=hello")!
        let masked = url.masked()
        XCTAssertTrue(masked.contains("token=***"))
        XCTAssertTrue(masked.contains("q=***"))
        XCTAssertFalse(masked.contains("secret"))
    }
}
