import XCTest
@testable import SwiftUtilsNetworking

final class WebSocketClientTests: XCTestCase {

    private let sampleURL = URL(string: "wss://example.com/socket")!

    // MARK: - WebSocketMessage / WebSocketEvent

    func testWebSocketMessageEquatable() {
        XCTAssertEqual(WebSocketMessage.text("hi"), WebSocketMessage.text("hi"))
        XCTAssertNotEqual(WebSocketMessage.text("hi"), WebSocketMessage.text("bye"))
        XCTAssertEqual(WebSocketMessage.data(Data([1, 2])), WebSocketMessage.data(Data([1, 2])))
        XCTAssertNotEqual(WebSocketMessage.text("1"), WebSocketMessage.data(Data([1])))
    }

    // MARK: - WebSocketError

    func testNotConnectedErrorDescription() {
        let error = WebSocketError.notConnected
        XCTAssertEqual(error.errorDescription, "The WebSocket is not connected.")
    }

    func testEncodingFailedErrorDescription() {
        let error = WebSocketError.encodingFailed
        XCTAssertEqual(error.errorDescription, "Failed to encode the value to send.")
    }

    // MARK: - Configuration defaults

    func testDefaultConfiguration() {
        let config = WebSocketClient.Configuration.default
        XCTAssertEqual(config.pingInterval, 25)
        XCTAssertTrue(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 5)
        XCTAssertEqual(config.reconnectBaseDelay, 1)
        XCTAssertEqual(config.reconnectMaxDelay, 30)
    }

    func testCustomConfiguration() {
        let config = WebSocketClient.Configuration(
            pingInterval: nil,
            autoReconnect: false,
            maxReconnectAttempts: 0,
            reconnectBaseDelay: 2,
            reconnectMaxDelay: 10
        )
        XCTAssertNil(config.pingInterval)
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 0)
    }

    // MARK: - decode(_:as:)

    struct Payload: Codable, Equatable {
        let id: Int
        let name: String
    }

    func testDecodeFromTextMessage() throws {
        let payload = Payload(id: 1, name: "swift-utils")
        let json = try JSONEncoder().encode(payload)
        let text = String(data: json, encoding: .utf8)!

        let decoded = try WebSocketClient.decode(.text(text), as: Payload.self)
        XCTAssertEqual(decoded, payload)
    }

    func testDecodeFromDataMessage() throws {
        let payload = Payload(id: 2, name: "binary")
        let json = try JSONEncoder().encode(payload)

        let decoded = try WebSocketClient.decode(.data(json), as: Payload.self)
        XCTAssertEqual(decoded, payload)
    }

    func testDecodeThrowsOnMalformedPayload() {
        XCTAssertThrowsError(try WebSocketClient.decode(.text("not json"), as: Payload.self))
    }

    // MARK: - Send without connecting

    func testSendTextThrowsNotConnectedBeforeConnect() async {
        let client = WebSocketClient(url: sampleURL)
        do {
            try await client.send("hello")
            XCTFail("Expected notConnected error")
        } catch let error as WebSocketError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSendEncodableThrowsNotConnectedBeforeConnect() async {
        let client = WebSocketClient(url: sampleURL)
        do {
            try await client.send(Payload(id: 1, name: "test"))
            XCTFail("Expected notConnected error")
        } catch let error as WebSocketError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Disconnect safety

    func testDisconnectWithoutConnectingDoesNotCrash() {
        let client = WebSocketClient(url: sampleURL)
        client.disconnect()
        // No assertion needed — this test passes if it doesn't crash or hang.
    }

    func testDisconnectIsIdempotent() {
        let client = WebSocketClient(url: sampleURL)
        client.disconnect()
        client.disconnect()
    }
}

extension WebSocketError: Equatable {
    public static func == (lhs: WebSocketError, rhs: WebSocketError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected), (.encodingFailed, .encodingFailed):
            return true
        default:
            return false
        }
    }
}
