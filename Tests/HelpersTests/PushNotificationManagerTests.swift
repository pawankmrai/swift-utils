import XCTest
@testable import SwiftUtilsHelpers

final class PushNotificationManagerTests: XCTestCase {

    private var manager: PushNotificationManager!

    override func setUp() {
        super.setUp()
        manager = PushNotificationManager()
    }

    override func tearDown() {
        manager.reset()
        manager.removeAllHandlers()
        manager = nil
        super.tearDown()
    }

    // MARK: - PushNotificationPayload parsing

    func testParsesStringAlert() {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": "You have a new message",
                "category": "CHAT_MESSAGE",
                "badge": 3,
                "sound": "default"
            ],
            "conversationId": "abc-123"
        ]

        let payload = PushNotificationPayload(userInfo: userInfo)

        XCTAssertNil(payload.title)
        XCTAssertEqual(payload.body, "You have a new message")
        XCTAssertEqual(payload.category, "CHAT_MESSAGE")
        XCTAssertEqual(payload.badge, 3)
        XCTAssertEqual(payload.sound, "default")
        XCTAssertEqual(payload.customData["conversationId"], "abc-123")
    }

    func testParsesDictionaryAlertWithTitleAndBody() {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "New comment",
                    "body": "Alice replied to your post"
                ],
                "thread-id": "post-42"
            ]
        ]

        let payload = PushNotificationPayload(userInfo: userInfo)

        XCTAssertEqual(payload.title, "New comment")
        XCTAssertEqual(payload.body, "Alice replied to your post")
        XCTAssertEqual(payload.threadIdentifier, "post-42")
    }

    func testMissingApsProducesEmptyPayload() {
        let payload = PushNotificationPayload(userInfo: ["foo": "bar"])
        XCTAssertNil(payload.title)
        XCTAssertNil(payload.body)
        XCTAssertNil(payload.category)
        XCTAssertEqual(payload.customData["foo"], "bar")
    }

    func testCustomDataExcludesApsKey() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": "hi"],
            "userId": "42",
            "screen": "profile"
        ]
        let payload = PushNotificationPayload(userInfo: userInfo)
        XCTAssertNil(payload.customData["aps"])
        XCTAssertEqual(payload.customData["userId"], "42")
        XCTAssertEqual(payload.customData["screen"], "profile")
    }

    // MARK: - Device token handling

    func testHandleDeviceTokenProducesHexString() {
        let tokenData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let hex = manager.handleDeviceToken(tokenData)

        XCTAssertEqual(hex, "deadbeef")
        XCTAssertEqual(manager.deviceToken, "deadbeef")
        XCTAssertEqual(manager.deviceTokenData, tokenData)
        XCTAssertNil(manager.registrationError)
    }

    func testHandleRegistrationFailureClearsToken() {
        _ = manager.handleDeviceToken(Data([0x01, 0x02]))
        struct DummyError: Error {}
        manager.handleRegistrationFailure(DummyError())

        XCTAssertNil(manager.deviceToken)
        XCTAssertNil(manager.deviceTokenData)
        XCTAssertNotNil(manager.registrationError)
    }

    func testResetClearsAllState() {
        _ = manager.handleDeviceToken(Data([0xAB]))
        manager.reset()
        XCTAssertNil(manager.deviceToken)
        XCTAssertNil(manager.deviceTokenData)
        XCTAssertNil(manager.registrationError)
    }

    // MARK: - Token updates stream

    func testTokenUpdatesYieldsExistingTokenImmediately() async {
        _ = manager.handleDeviceToken(Data([0x01, 0x02, 0x03]))

        let stream = manager.tokenUpdates()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first, "010203")
    }

    func testTokenUpdatesYieldsSubsequentTokens() async {
        let stream = manager.tokenUpdates()
        var iterator = stream.makeAsyncIterator()

        // No token yet, so the first update should be the one we set next.
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000)
            _ = manager.handleDeviceToken(Data([0xFF]))
        }

        let first = await iterator.next()
        XCTAssertEqual(first, "ff")
    }

    // MARK: - Payload routing

    func testHandleDispatchesToMatchingCategoryHandler() {
        let expectation = expectation(description: "chat handler invoked")
        manager.onNotification(category: "CHAT_MESSAGE") { payload in
            XCTAssertEqual(payload.customData["conversationId"], "abc-123")
            expectation.fulfill()
        }

        let handled = manager.handle(userInfo: [
            "aps": ["alert": "hi", "category": "CHAT_MESSAGE"],
            "conversationId": "abc-123"
        ])

        XCTAssertTrue(handled)
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleFallsBackToDefaultHandlerForUnknownCategory() {
        let expectation = expectation(description: "default handler invoked")
        manager.onNotification(category: "CHAT_MESSAGE") { _ in
            XCTFail("Should not invoke chat handler")
        }
        manager.onUnhandledNotification { payload in
            XCTAssertEqual(payload.category, "PROMO")
            expectation.fulfill()
        }

        let handled = manager.handle(userInfo: [
            "aps": ["alert": "sale!", "category": "PROMO"]
        ])

        XCTAssertTrue(handled)
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleReturnsFalseWhenNoHandlerRegistered() {
        let handled = manager.handle(userInfo: [
            "aps": ["alert": "no handlers here"]
        ])
        XCTAssertFalse(handled)
    }

    func testRemoveAllHandlersClearsRouting() {
        manager.onNotification(category: "CHAT_MESSAGE") { _ in
            XCTFail("Should not be invoked after removal")
        }
        manager.onUnhandledNotification { _ in
            XCTFail("Should not be invoked after removal")
        }
        manager.removeAllHandlers()

        let handled = manager.handle(userInfo: [
            "aps": ["alert": "hi", "category": "CHAT_MESSAGE"]
        ])
        XCTAssertFalse(handled)
    }
}
