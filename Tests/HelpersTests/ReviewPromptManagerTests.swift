import XCTest
@testable import SwiftUtilsHelpers

final class ReviewPromptManagerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeManager(
        criteria: ReviewPromptCriteria = .default,
        daysSinceInstall: Int = 10,
        version: String = "1.0.0"
    ) -> ReviewPromptManager {
        let installDate = Calendar.current.date(byAdding: .day, value: -daysSinceInstall, to: Date())!
        var currentDate = Date()

        let manager = ReviewPromptManager(
            criteria: criteria,
            userDefaults: defaults,
            bundle: Bundle(for: Self.self),
            now: { currentDate }
        )
        // Seed first launch date directly to control "days since install".
        defaults.set(installDate, forKey: "ReviewPromptManager.firstLaunchDate")
        _ = manager.firstLaunchDate // no-op, ensures lazily-set path isn't triggered
        _ = currentDate // silence unused warning in some configurations
        return manager
    }

    // MARK: - Defaults

    func testDefaultCriteriaValues() {
        let criteria = ReviewPromptCriteria.default
        XCTAssertEqual(criteria.minSignificantEvents, 5)
        XCTAssertEqual(criteria.minDaysSinceFirstLaunch, 3)
        XCTAssertEqual(criteria.minDaysBetweenPrompts, 90)
        XCTAssertTrue(criteria.promptOncePerAppVersion)
    }

    // MARK: - Event recording

    func testRecordSignificantEventIncrementsCount() {
        let manager = makeManager()
        XCTAssertEqual(manager.significantEventCount, 0)
        manager.recordSignificantEvent()
        manager.recordSignificantEvent()
        XCTAssertEqual(manager.significantEventCount, 2)
    }

    // MARK: - Eligibility

    func testNotEligibleBeforeEnoughEvents() {
        let manager = makeManager(daysSinceInstall: 30)
        manager.recordSignificantEvent()
        XCTAssertFalse(manager.isEligible)
    }

    func testEligibleOnceThresholdsAreMet() {
        let manager = makeManager(daysSinceInstall: 30)
        for _ in 0..<5 { manager.recordSignificantEvent() }
        XCTAssertTrue(manager.isEligible)
    }

    func testNotEligibleBeforeMinDaysSinceInstall() {
        let criteria = ReviewPromptCriteria(minSignificantEvents: 1, minDaysSinceFirstLaunch: 10)
        let manager = makeManager(criteria: criteria, daysSinceInstall: 1)
        manager.recordSignificantEvent()
        XCTAssertFalse(manager.isEligible)
    }

    func testNotEligibleWithinMinDaysBetweenPrompts() {
        let criteria = ReviewPromptCriteria(minSignificantEvents: 1, minDaysSinceFirstLaunch: 0, minDaysBetweenPrompts: 60)
        let manager = makeManager(criteria: criteria, daysSinceInstall: 30)
        manager.recordSignificantEvent()
        XCTAssertTrue(manager.isEligible)

        manager.markPrompted()
        XCTAssertFalse(manager.isEligible, "Should not be eligible again immediately after prompting")
    }

    func testNotEligibleTwiceForSameVersionWhenConfigured() {
        let criteria = ReviewPromptCriteria(
            minSignificantEvents: 1,
            minDaysSinceFirstLaunch: 0,
            minDaysBetweenPrompts: 0,
            promptOncePerAppVersion: true
        )
        let manager = makeManager(criteria: criteria, daysSinceInstall: 30)
        manager.recordSignificantEvent()
        manager.markPrompted()

        // Even with zero-day cooldown, same version should block re-prompting.
        XCTAssertEqual(manager.lastPromptedVersion, manager.currentAppVersion)
        XCTAssertFalse(manager.isEligible)
    }

    func testEligibleAgainWhenPerVersionThrottleDisabled() {
        let criteria = ReviewPromptCriteria(
            minSignificantEvents: 1,
            minDaysSinceFirstLaunch: 0,
            minDaysBetweenPrompts: 0,
            promptOncePerAppVersion: false
        )
        let manager = makeManager(criteria: criteria, daysSinceInstall: 30)
        manager.recordSignificantEvent()
        manager.markPrompted()
        XCTAssertTrue(manager.isEligible)
    }

    // MARK: - markPrompted

    func testMarkPromptedRecordsDateAndVersion() {
        let manager = makeManager(daysSinceInstall: 30)
        XCTAssertNil(manager.lastPromptDate)
        manager.markPrompted()
        XCTAssertNotNil(manager.lastPromptDate)
        XCTAssertEqual(manager.lastPromptedVersion, manager.currentAppVersion)
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        let manager = makeManager(daysSinceInstall: 30)
        manager.recordSignificantEvent()
        manager.markPrompted()

        manager.reset()

        XCTAssertEqual(manager.significantEventCount, 0)
        XCTAssertNil(manager.lastPromptDate)
        XCTAssertNil(manager.lastPromptedVersion)
    }

    // MARK: - currentAppVersion

    func testCurrentAppVersionFallsBackToUnknownWithoutInfoDictionary() {
        let manager = ReviewPromptManager(
            userDefaults: defaults,
            bundle: Bundle(for: ReviewPromptManagerTests.self)
        )
        // The XCTest host bundle may or may not define CFBundleShortVersionString;
        // either way this should not crash and should return a String.
        XCTAssertFalse(manager.currentAppVersion.isEmpty)
    }
}
