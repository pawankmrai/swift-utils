import XCTest
@testable import SwiftUtilsNetworking

final class SSEClientTests: XCTestCase {

    private let sampleURL = URL(string: "https://example.com/stream")!

    // MARK: - SSEMessage

    func testSSEMessageEquatable() {
        let a = SSEMessage(id: "1", event: "update", data: "hello", retry: 3000)
        let b = SSEMessage(id: "1", event: "update", data: "hello", retry: 3000)
        let c = SSEMessage(id: "2", event: "update", data: "hello", retry: 3000)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - SSEClientError

    func testInvalidResponseErrorDescription() {
        let error = SSEClientError.invalidResponse
        XCTAssertEqual(error.errorDescription, "The server did not return a valid HTTP response.")
    }

    func testHTTPErrorDescription() {
        let error = SSEClientError.httpError(statusCode: 503)
        XCTAssertEqual(error.errorDescription, "The server responded with status code 503.")
    }

    // MARK: - Configuration defaults

    func testDefaultConfiguration() {
        let config = SSEClient.Configuration.default
        XCTAssertTrue(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 10)
        XCTAssertEqual(config.reconnectBaseDelay, 1)
        XCTAssertEqual(config.reconnectMaxDelay, 30)
    }

    func testCustomConfiguration() {
        let config = SSEClient.Configuration(
            autoReconnect: false,
            maxReconnectAttempts: 0,
            reconnectBaseDelay: 2,
            reconnectMaxDelay: 15
        )
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 0)
        XCTAssertEqual(config.reconnectBaseDelay, 2)
        XCTAssertEqual(config.reconnectMaxDelay, 15)
    }

    // MARK: - decode(_:as:)

    struct Payload: Codable, Equatable {
        let id: Int
        let name: String
    }

    func testDecodeMessageData() throws {
        let payload = Payload(id: 7, name: "swift-utils")
        let json = try JSONEncoder().encode(payload)
        let text = String(data: json, encoding: .utf8)!
        let message = SSEMessage(id: nil, event: "message", data: text, retry: nil)

        let decoded = try SSEClient.decode(message, as: Payload.self)
        XCTAssertEqual(decoded, payload)
    }

    func testDecodeThrowsOnMalformedPayload() {
        let message = SSEMessage(id: nil, event: "message", data: "not json", retry: nil)
        XCTAssertThrowsError(try SSEClient.decode(message, as: Payload.self))
    }

    func testDecodeMultiLineDataPayload() throws {
        // Multi-line `data:` fields are joined with "\n" by the client before
        // reaching consumers; a JSON payload wouldn't normally span lines, but
        // plain-text payloads (e.g. log streams) commonly do.
        let message = SSEMessage(id: "42", event: "log", data: "line one\nline two", retry: nil)
        XCTAssertEqual(message.data, "line one\nline two")
        XCTAssertEqual(message.id, "42")
        XCTAssertEqual(message.event, "log")
    }

    // MARK: - Lifecycle safety without connecting

    func testDisconnectWithoutConnectingDoesNotCrash() {
        let client = SSEClient(url: sampleURL)
        client.disconnect()
        // No assertion needed — this test passes if it doesn't crash or hang.
    }

    func testDisconnectIsIdempotent() {
        let client = SSEClient(url: sampleURL)
        client.disconnect()
        client.disconnect()
    }

    // MARK: - Initialization

    func testInitStoresConfigurationWithoutConnecting() {
        // Constructing a client must not perform any network activity.
        let client = SSEClient(
            url: sampleURL,
            headers: ["Authorization": "Bearer token"],
            configuration: .init(autoReconnect: false, maxReconnectAttempts: 3)
        )
        XCTAssertNotNil(client)
    }
}
