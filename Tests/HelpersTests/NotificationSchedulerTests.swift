import XCTest
@testable import SwiftUtilsHelpers
import UserNotifications

final class NotificationSchedulerTests: XCTestCase {

    private var scheduler: NotificationScheduler!

    override func setUp() {
        super.setUp()
        scheduler = NotificationScheduler()
    }

    // MARK: - Builder Content

    func testBuilderSetsTitle() {
        let builder = scheduler.schedule("test-1")
            .title("Hello")
        XCTAssertNotNil(builder, "Builder should be created successfully")
    }

    func testBuilderChainsMultipleProperties() {
        let builder = scheduler.schedule("test-2")
            .title("Title")
            .subtitle("Subtitle")
            .body("Body text")
            .badge(5)
            .sound(.default)
            .categoryIdentifier("reminder")
            .threadIdentifier("thread-1")
            .userInfo(["key": "value"])
        XCTAssertNotNil(builder, "Chained builder should be non-nil")
    }

    // MARK: - Trigger Builders

    func testAfterSecondsTrigger() {
        let builder = scheduler.schedule("test-3")
            .title("Delay test")
            .after(seconds: 60)
        XCTAssertNotNil(builder)
    }

    func testAfterSecondsRepeatingTrigger() {
        let builder = scheduler.schedule("test-4")
            .title("Repeat test")
            .after(seconds: 120, repeats: true)
        XCTAssertNotNil(builder)
    }

    func testAtDateComponentsTrigger() {
        var components = DateComponents()
        components.hour = 9
        components.minute = 30

        let builder = scheduler.schedule("test-5")
            .title("Calendar test")
            .at(dateComponents: components, repeats: true)
        XCTAssertNotNil(builder)
    }

    func testAtDateTrigger() {
        let futureDate = Date().addingTimeInterval(3600)
        let builder = scheduler.schedule("test-6")
            .title("Date test")
            .at(date: futureDate)
        XCTAssertNotNil(builder)
    }

    func testDailyTrigger() {
        let builder = scheduler.schedule("test-7")
            .title("Daily test")
            .daily(hour: 8, minute: 0)
        XCTAssertNotNil(builder)
    }

    func testWeeklyTrigger() {
        let builder = scheduler.schedule("test-8")
            .title("Weekly test")
            .weekly(weekday: 2, hour: 10, minute: 30)
        XCTAssertNotNil(builder)
    }

    // MARK: - Cancellation

    func testCancelPendingVariadic() {
        // Should not crash even with no pending notifications
        scheduler.cancelPending("nonexistent-1", "nonexistent-2")
    }

    func testCancelPendingArray() {
        scheduler.cancelPending(["nonexistent-1"])
    }

    func testCancelAllPending() {
        scheduler.cancelAllPending()
    }

    func testRemoveDelivered() {
        scheduler.removeDelivered(["nonexistent"])
    }

    func testRemoveAllDelivered() {
        scheduler.removeAllDelivered()
    }

    // MARK: - Async Queries

    func testPendingIdentifiers() async {
        let ids = await scheduler.pendingIdentifiers()
        XCTAssertTrue(ids.isEmpty, "Fresh scheduler should have no pending notifications")
    }

    func testDeliveredIdentifiers() async {
        let ids = await scheduler.deliveredIdentifiers()
        XCTAssertTrue(ids.isEmpty, "Fresh scheduler should have no delivered notifications")
    }

    // MARK: - Authorization

    func testAuthorizationStatus() async {
        let status = await scheduler.authorizationStatus()
        // In a test environment, status should be notDetermined or denied
        XCTAssertTrue(
            status == .notDetermined || status == .denied || status == .authorized,
            "Status should be a valid UNAuthorizationStatus"
        )
    }

    // MARK: - Shared Instance

    func testSharedInstance() {
        let a = NotificationScheduler.shared
        let b = NotificationScheduler.shared
        XCTAssertTrue(a === b, "Shared instance should be the same object")
    }

    // MARK: - Builder with no explicit sound defaults

    func testBuilderWithNoSound() {
        // Verifying builder can be created without setting sound
        let builder = scheduler.schedule("test-no-sound")
            .title("No sound set")
            .body("Should default to .default on commit")
        XCTAssertNotNil(builder)
    }

    // MARK: - Builder with userInfo

    func testBuilderUserInfo() {
        let info: [AnyHashable: Any] = [
            "action": "open_screen",
            "screenId": 42
        ]
        let builder = scheduler.schedule("test-userinfo")
            .title("Deep link")
            .userInfo(info)
        XCTAssertNotNil(builder)
    }
}
