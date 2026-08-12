import XCTest
@testable import SwiftUtilsNetworking

final class APIErrorMapperTests: XCTestCase {

    private func response(status: Int, url: String = "https://api.example.com/thing") -> URLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    // MARK: - isSuccess

    func testIsSuccessRangeBoundaries() {
        XCTAssertTrue(APIErrorMapper.isSuccess(200))
        XCTAssertTrue(APIErrorMapper.isSuccess(299))
        XCTAssertFalse(APIErrorMapper.isSuccess(199))
        XCTAssertFalse(APIErrorMapper.isSuccess(300))
        XCTAssertFalse(APIErrorMapper.isSuccess(404))
    }

    // MARK: - validate: success paths

    func testValidateDoesNotThrowFor2xx() throws {
        try APIErrorMapper.validate(data: Data(), response: response(status: 204), as: ProblemDetails.self)
    }

    func testValidateDoesNotThrowForNonHTTPResponse() throws {
        let plain = URLResponse(url: URL(string: "https://example.com")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        try APIErrorMapper.validate(data: Data(), response: plain, as: ProblemDetails.self)
    }

    // MARK: - validate: structured error bodies

    func testValidateThrowsClientErrorWithDecodedProblemDetails() {
        let json = #"{"title":"Not Found","status":404,"detail":"No such widget"}"#.data(using: .utf8)!

        XCTAssertThrowsError(
            try APIErrorMapper.validate(data: json, response: response(status: 404), as: ProblemDetails.self)
        ) { error in
            guard case .clientError(let status, let body)? = error as? StructuredAPIError<ProblemDetails> else {
                return XCTFail("Expected .clientError, got \(error)")
            }
            XCTAssertEqual(status, 404)
            XCTAssertEqual(body?.detail, "No such widget")
            XCTAssertEqual(body?.title, "Not Found")
        }
    }

    func testValidateThrowsServerErrorForStatus5xx() {
        let json = #"{"title":"Internal Error"}"#.data(using: .utf8)!

        XCTAssertThrowsError(
            try APIErrorMapper.validate(data: json, response: response(status: 503), as: ProblemDetails.self)
        ) { error in
            guard case .serverError(let status, let body)? = error as? StructuredAPIError<ProblemDetails> else {
                return XCTFail("Expected .serverError, got \(error)")
            }
            XCTAssertEqual(status, 503)
            XCTAssertEqual(body?.title, "Internal Error")
        }
    }

    func testValidateThrowsUndecodableBodyWhenErrorIsNotJSON() {
        let raw = "<html>502 Bad Gateway</html>".data(using: .utf8)!

        XCTAssertThrowsError(
            try APIErrorMapper.validate(data: raw, response: response(status: 502), as: ProblemDetails.self)
        ) { error in
            guard case .undecodableBody(let status, let body)? = error as? StructuredAPIError<ProblemDetails> else {
                return XCTFail("Expected .undecodableBody, got \(error)")
            }
            XCTAssertEqual(status, 502)
            XCTAssertEqual(body, raw)
        }
    }

    func testValidateTreatsEmptyBodyAsMissingRatherThanUndecodable() {
        XCTAssertThrowsError(
            try APIErrorMapper.validate(data: Data(), response: response(status: 401), as: ProblemDetails.self)
        ) { error in
            guard case .clientError(let status, let body)? = error as? StructuredAPIError<ProblemDetails> else {
                return XCTFail("Expected .clientError for empty body, got \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertNil(body)
        }
    }

    // MARK: - validate: custom error body types

    func testValidateWithCustomErrorBodyType() {
        struct CustomError: Decodable, Sendable {
            let code: String
            let message: String
        }

        let json = #"{"code":"AUTH_EXPIRED","message":"Token expired"}"#.data(using: .utf8)!

        XCTAssertThrowsError(
            try APIErrorMapper.validate(data: json, response: response(status: 401), as: CustomError.self)
        ) { error in
            guard case .clientError(_, let body)? = error as? StructuredAPIError<CustomError> else {
                return XCTFail("Expected .clientError, got \(error)")
            }
            XCTAssertEqual(body?.code, "AUTH_EXPIRED")
            XCTAssertEqual(body?.message, "Token expired")
        }
    }

    // MARK: - decode

    func testDecodeReturnsModelOnSuccess() throws {
        struct Widget: Decodable, Equatable {
            let id: Int
            let name: String
        }

        let json = #"{"id":1,"name":"Sprocket"}"#.data(using: .utf8)!
        let widget = try APIErrorMapper.decode(Widget.self, from: json, response: response(status: 200))
        XCTAssertEqual(widget, Widget(id: 1, name: "Sprocket"))
    }

    func testDecodeThrowsStructuredErrorOnFailureStatus() {
        struct Widget: Decodable {}
        let json = #"{"title":"Forbidden"}"#.data(using: .utf8)!

        XCTAssertThrowsError(
            try APIErrorMapper.decode(Widget.self, from: json, response: response(status: 403))
        ) { error in
            XCTAssertTrue(error is StructuredAPIError<ProblemDetails>)
        }
    }

    // MARK: - StructuredAPIError

    func testStatusCodeAccessor() {
        let clientError = StructuredAPIError<ProblemDetails>.clientError(status: 400, body: nil)
        XCTAssertEqual(clientError.statusCode, 400)

        let transportError = StructuredAPIError<ProblemDetails>.transport(URLError(.notConnectedToInternet))
        XCTAssertNil(transportError.statusCode)
    }

    func testErrorDescriptionPrefersProblemDetailDetail() {
        let problem = ProblemDetails(title: "Bad Request", status: 400, detail: "Missing 'name' field")
        let error = StructuredAPIError<ProblemDetails>.clientError(status: 400, body: problem)
        XCTAssertEqual(error.errorDescription, "Missing 'name' field")
    }

    func testErrorDescriptionFallsBackToTitleThenGenericMessage() {
        let titleOnly = StructuredAPIError<ProblemDetails>.clientError(
            status: 400,
            body: ProblemDetails(title: "Bad Request")
        )
        XCTAssertEqual(titleOnly.errorDescription, "Bad Request")

        let noBody = StructuredAPIError<ProblemDetails>.serverError(status: 500, body: nil)
        XCTAssertEqual(noBody.errorDescription, "Request failed with status 500.")
    }

    // MARK: - mapTransportError

    func testMapTransportErrorWrapsURLError() {
        let mapped: StructuredAPIError<ProblemDetails> = APIErrorMapper.mapTransportError(URLError(.timedOut))
        guard case .transport(let urlError) = mapped else {
            return XCTFail("Expected .transport")
        }
        XCTAssertEqual(urlError.code, .timedOut)
    }

    func testMapTransportErrorPassesThroughExistingStructuredError() {
        let original = StructuredAPIError<ProblemDetails>.clientError(status: 429, body: nil)
        let mapped: StructuredAPIError<ProblemDetails> = APIErrorMapper.mapTransportError(original)
        XCTAssertEqual(mapped.statusCode, 429)
    }
}
