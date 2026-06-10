import XCTest
@testable import SwiftUtilsHelpers

// MARK: - Test Fixtures

struct TestEvent: AnalyticsEvent {
    let name: String
    let properties: [String: Any]
    init(_ name: String, _ properties: [String: Any] = [:]) {
        self.name = name
        self.properties = properties
    }
}

final class SpyBackend: AnalyticsBackend, @unchecked Sendable {
    var trackedEvents: [(name: String, properties: [String: Any])] = []
    var identifiedUsers: [(userId: String, traits: [String: Any])] = []
    var resetCount = 0

    func track(event: any AnalyticsEvent, mergedProperties: [String: Any]) {
        trackedEvents.append((event.name, mergedProperties))
    }
    func identify(userId: String, traits: [String: Any]) {
        identifiedUsers.append((userId, traits))
    }
    func reset() { resetCount += 1 }
}

// MARK: - Tests

final class AnalyticsTrackerTests: XCTestCase {

    var tracker: AnalyticsTracker!
    var spy: SpyBackend!

    override func setUp() {
        super.setUp()
        tracker = AnalyticsTracker()
        spy = SpyBackend()
        tracker.addBackend(spy)
    }

    // MARK: - Basic Tracking

    func testTrackStructuredEvent() {
        tracker.track(event: TestEvent("button_tapped", ["buttonId": "cta"]))
        XCTAssertEqual(spy.trackedEvents.count, 1)
        XCTAssertEqual(spy.trackedEvents[0].name, "button_tapped")
        XCTAssertEqual(spy.trackedEvents[0].properties["buttonId"] as? String, "cta")
    }

    func testTrackFreeformEvent() {
        tracker.track("page_view", properties: ["page": "home"])
        XCTAssertEqual(spy.trackedEvents.count, 1)
        XCTAssertEqual(spy.trackedEvents[0].name, "page_view")
        XCTAssertEqual(spy.trackedEvents[0].properties["page"] as? String, "home")
    }

    func testEventCountIncrements() {
        tracker.track("e1")
        tracker.track("e2")
        tracker.track("e3")
        XCTAssertEqual(tracker.trackedEventCount, 3)
        XCTAssertEqual(spy.trackedEvents[2].properties["eventIndex"] as? Int, 3)
    }

    // MARK: - Global Properties

    func testGlobalPropertyMergedIntoEvent() {
        tracker.set(globalProperty: "platform", value: "iOS")
        tracker.track("test_event")
        XCTAssertEqual(spy.trackedEvents[0].properties["platform"] as? String, "iOS")
    }

    func testRemoveGlobalProperty() {
        tracker.set(globalProperty: "key", value: "value")
        tracker.set(globalProperty: "key", value: nil)
        tracker.track("test_event")
        XCTAssertNil(spy.trackedEvents[0].properties["key"])
    }

    func testSetGlobalPropertiesReplacesPrevious() {
        tracker.set(globalProperty: "old", value: "should_be_gone")
        tracker.setGlobalProperties(["new": "here"])
        tracker.track("test_event")
        XCTAssertNil(spy.trackedEvents[0].properties["old"])
        XCTAssertEqual(spy.trackedEvents[0].properties["new"] as? String, "here")
    }

    func testEventPropertiesOverrideGlobals() {
        tracker.set(globalProperty: "source", value: "global")
        tracker.track("test_event", properties: ["source": "event_level"])
        XCTAssertEqual(spy.trackedEvents[0].properties["source"] as? String, "event_level")
    }

    // MARK: - Session ID

    func testSessionIdPresentInEveryEvent() {
        let sid = tracker.currentSessionId
        tracker.track("e1")
        tracker.track("e2")
        XCTAssertEqual(spy.trackedEvents[0].properties["sessionId"] as? String, sid)
        XCTAssertEqual(spy.trackedEvents[1].properties["sessionId"] as? String, sid)
    }

    // MARK: - Identity

    func testIdentifyForwardsToBackend() {
        tracker.identify(userId: "user_42", traits: ["plan": "pro"])
        XCTAssertEqual(spy.identifiedUsers.count, 1)
        XCTAssertEqual(spy.identifiedUsers[0].userId, "user_42")
        XCTAssertEqual(spy.identifiedUsers[0].traits["plan"] as? String, "pro")
    }

    func testIdentifyAddsUserIdToGlobalProperties() {
        tracker.identify(userId: "user_42")
        tracker.track("test_event")
        XCTAssertEqual(spy.trackedEvents[0].properties["userId"] as? String, "user_42")
    }

    // MARK: - Reset

    func testResetClearsUserIdAndCounter() {
        tracker.identify(userId: "user_42")
        tracker.track("e1")
        tracker.reset()

        XCTAssertEqual(tracker.trackedEventCount, 0)
        XCTAssertNil(tracker.currentGlobalProperties["userId"])
        XCTAssertEqual(spy.resetCount, 1)
    }

    func testResetChangesSessionId() {
        let oldSid = tracker.currentSessionId
        tracker.reset()
        XCTAssertNotEqual(tracker.currentSessionId, oldSid)
    }

    // MARK: - Multiple Backends

    func testMultipleBackendsReceiveEvents() {
        let spy2 = SpyBackend()
        tracker.addBackend(spy2)
        tracker.track("multi_test")
        XCTAssertEqual(spy.trackedEvents.count, 1)
        XCTAssertEqual(spy2.trackedEvents.count, 1)
    }

    func testRemoveAllBackends() {
        tracker.removeAllBackends()
        tracker.track("silent_event")
        XCTAssertEqual(spy.trackedEvents.count, 0)
    }

    // MARK: - Thread Safety

    func testConcurrentTrackingIsSafe() {
        let expectation = expectation(description: "concurrent tracking")
        expectation.expectedFulfillmentCount = 100
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        for i in 0..<100 {
            queue.async {
                self.tracker.track("concurrent_event_\(i)")
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 5)
        XCTAssertEqual(tracker.trackedEventCount, 100)
    }
}
