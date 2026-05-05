import XCTest
@testable import SwiftUtils

final class APIClientTests: XCTestCase {

    var client: APIClient!

    override func setUp() {
        super.setUp()
        client = APIClient(baseURL: URL(string: "https://api.example.com")!)
    }

    func testDefaultHeaders() {
        XCTAssertEqual(client.defaultHeaders["Content-Type"], "application/json")
        XCTAssertEqual(client.defaultHeaders["Accept"], "application/json")
    }

    func testBaseURLIsStored() {
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.example.com")
    }

    func testAPIErrorDescriptions() {
        let invalidURL = APIError.invalidURL("/test")
        XCTAssertTrue(invalidURL.errorDescription?.contains("/test") ?? false)

        let invalidResponse = APIError.invalidResponse
        XCTAssertEqual(invalidResponse.errorDescription, "Invalid response received")

        let httpError = APIError.httpError(statusCode: 404, data: Data())
        XCTAssertTrue(httpError.errorDescription?.contains("404") ?? false)
    }

    func testDecodeErrorBody() {
        struct ErrorResponse: Decodable {
            let message: String
        }

        let json = #"{"message":"Not found"}"#.data(using: .utf8)!
        let error = APIError.httpError(statusCode: 404, data: json)

        let decoded = error.decodeErrorBody(as: ErrorResponse.self)
        XCTAssertEqual(decoded?.message, "Not found")
    }

    func testDecodeErrorBodyReturnsNilForNonHTTPError() {
        let error = APIError.invalidResponse
        struct ErrorResponse: Decodable { let message: String }

        let decoded = error.decodeErrorBody(as: ErrorResponse.self)
        XCTAssertNil(decoded)
    }

    func testCustomDecoderAndEncoder() {
        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .useDefaultKeys

        let customEncoder = JSONEncoder()
        customEncoder.outputFormatting = .prettyPrinted

        let customClient = APIClient(
            baseURL: URL(string: "https://api.test.com")!,
            decoder: customDecoder,
            encoder: customEncoder
        )

        XCTAssertNotNil(customClient)
        XCTAssertEqual(customClient.baseURL.absoluteString, "https://api.test.com")
    }
}
