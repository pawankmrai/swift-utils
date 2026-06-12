import XCTest
@testable import SwiftUtilsNetworking

final class RequestBuilderTests: XCTestCase {

    // MARK: - Initialisation

    func testInitWithValidURL() throws {
        let url = URL(string: "https://example.com")!
        let request = try RequestBuilder(url: url).build()
        XCTAssertEqual(request.url?.host, "example.com")
    }

    func testInitWithValidURLString() throws {
        let request = try RequestBuilder(url: "https://example.com/path").build()
        XCTAssertEqual(request.url?.path, "/path")
    }

    func testInitWithInvalidURLStringThrows() {
        XCTAssertThrowsError(try RequestBuilder(url: "not a valid url !!")) { error in
            guard case RequestBuilder.BuilderError.invalidURL = error else {
                XCTFail("Expected invalidURL error")
                return
            }
        }
    }

    // MARK: - HTTP Method

    func testDefaultMethodIsGET() throws {
        let request = try RequestBuilder(url: "https://example.com").build()
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testSettingPostMethod() throws {
        let request = try RequestBuilder(url: "https://example.com")
            .method(.post)
            .build()
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testAllMethodsRoundtrip() throws {
        let methods: [RequestBuilder.HTTPMethod] = [.get, .post, .put, .patch, .delete, .head, .options]
        for m in methods {
            let req = try RequestBuilder(url: "https://example.com").method(m).build()
            XCTAssertEqual(req.httpMethod, m.rawValue, "Failed for method \(m)")
        }
    }

    // MARK: - Headers

    func testSingleHeader() throws {
        let request = try RequestBuilder(url: "https://example.com")
            .header("Authorization", value: "Bearer token123")
            .build()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token123")
    }

    func testMultipleHeadersMerge() throws {
        let request = try RequestBuilder(url: "https://example.com")
            .headers(["X-App": "1.0", "Accept": "application/json"])
            .build()
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App"), "1.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testHeaderOverwrite() throws {
        let request = try RequestBuilder(url: "https://example.com")
            .header("Accept", value: "text/plain")
            .header("Accept", value: "application/json")
            .build()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    // MARK: - Query Parameters

    func testSingleQueryItem() throws {
        let request = try RequestBuilder(url: "https://example.com/search")
            .query("q", value: "swift")
            .build()
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let item = components?.queryItems?.first { $0.name == "q" }
        XCTAssertEqual(item?.value, "swift")
    }

    func testMultipleQueryItems() throws {
        let request = try RequestBuilder(url: "https://example.com/search")
            .query("q", value: "swift")
            .query("page", value: "2")
            .build()
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.count, 2)
    }

    func testQueryParametersDictionary() throws {
        let request = try RequestBuilder(url: "https://example.com/list")
            .queryParameters(["sort": "asc", "limit": "10"])
            .build()
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let names = components?.queryItems?.map(\.name) ?? []
        XCTAssertTrue(names.contains("sort"))
        XCTAssertTrue(names.contains("limit"))
    }

    func testExistingQueryParamsPreserved() throws {
        let request = try RequestBuilder(url: "https://example.com/search?existing=1")
            .query("new", value: "2")
            .build()
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.count, 2)
    }

    // MARK: - Body

    func testRawDataBody() throws {
        let data = "hello".data(using: .utf8)!
        let request = try RequestBuilder(url: "https://example.com")
            .method(.post)
            .body(data: data)
            .build()
        XCTAssertEqual(request.httpBody, data)
    }

    func testEncodableBodySetsContentType() throws {
        struct Payload: Encodable { let name: String }
        let request = try RequestBuilder(url: "https://example.com")
            .method(.post)
            .body(Payload(name: "Alice"))
            .build()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.httpBody)
    }

    func testEncodableBodyDoesNotOverrideExistingContentType() throws {
        struct Payload: Encodable { let name: String }
        let request = try RequestBuilder(url: "https://example.com")
            .method(.post)
            .header("Content-Type", value: "application/vnd.api+json")
            .body(Payload(name: "Bob"))
            .build()
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/vnd.api+json")
    }

    func testEncodableBodyRoundtrip() throws {
        struct Payload: Codable { let value: Int }
        let request = try RequestBuilder(url: "https://example.com")
            .method(.post)
            .body(Payload(value: 42))
            .build()
        let decoded = try JSONDecoder().decode(Payload.self, from: request.httpBody!)
        XCTAssertEqual(decoded.value, 42)
    }

    // MARK: - Timeout

    func testDefaultTimeout() throws {
        let request = try RequestBuilder(url: "https://example.com").build()
        XCTAssertEqual(request.timeoutInterval, 60)
    }

    func testCustomTimeout() throws {
        let request = try RequestBuilder(url: "https://example.com")
            .timeout(15)
            .build()
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    // MARK: - Cache Policy

    func testDefaultCachePolicy() throws {
        let request = try RequestBuilder(url: "https://example.com").build()
        XCTAssertEqual(request.cachePolicy, .useProtocolCachePolicy)
    }

    func testCustomCachePolicy() throws {
        let request = try RequestBuilder(url: "https://example.com")
            .cachePolicy(.reloadIgnoringLocalCacheData)
            .build()
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    // MARK: - Chaining

    func testFullChain() throws {
        struct Body: Encodable { let key: String }
        let request = try RequestBuilder(url: "https://api.example.com/items")
            .method(.post)
            .header("Authorization", value: "Bearer xyz")
            .header("X-Version", value: "2")
            .query("dry_run", value: "true")
            .body(Body(key: "value"))
            .timeout(20)
            .cachePolicy(.reloadIgnoringLocalCacheData)
            .build()

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xyz")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Version"), "2")
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertNotNil(request.httpBody)
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first?.name, "dry_run")
    }
}
