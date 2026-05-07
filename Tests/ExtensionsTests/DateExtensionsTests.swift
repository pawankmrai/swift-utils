import XCTest
@testable import SwiftUtilsExtensions

final class DateExtensionsTests: XCTestCase {

    // MARK: - Helpers

    private func date(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = Calendar.current.timeZone
        return Calendar.current.date(from: components)!
    }

    // MARK: - Component Access

    func testYearComponent() {
        let d = date(year: 2025, month: 6, day: 15)
        XCTAssertEqual(d.year, 2025)
    }

    func testMonthComponent() {
        let d = date(year: 2025, month: 3, day: 10)
        XCTAssertEqual(d.month, 3)
    }

    func testDayComponent() {
        let d = date(year: 2025, month: 1, day: 28)
        XCTAssertEqual(d.day, 28)
    }

    func testHourComponent() {
        let d = date(year: 2025, month: 1, day: 1, hour: 14)
        XCTAssertEqual(d.hour, 14)
    }

    func testMinuteComponent() {
        let d = date(year: 2025, month: 1, day: 1, hour: 0, minute: 45)
        XCTAssertEqual(d.minute, 45)
    }

    // MARK: - Formatting

    func testFormattedWithCustomPattern() {
        let d = date(year: 2025, month: 3, day: 15)
        let result = d.formatted(as: "yyyy-MM-dd", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(result, "2025-03-15")
    }

    func testFormattedWithMonthName() {
        let d = date(year: 2025, month: 12, day: 25)
        let result = d.formatted(as: "MMM d, yyyy", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(result, "Dec 25, 2025")
    }

    // MARK: - Day Comparisons

    func testIsSameDay() {
        let morning = date(year: 2025, month: 5, day: 7, hour: 8)
        let evening = date(year: 2025, month: 5, day: 7, hour: 20)
        XCTAssertTrue(morning.isSameDay(as: evening))
    }

    func testIsSameDayDifferentDays() {
        let day1 = date(year: 2025, month: 5, day: 7)
        let day2 = date(year: 2025, month: 5, day: 8)
        XCTAssertFalse(day1.isSameDay(as: day2))
    }

    func testIsToday() {
        XCTAssertTrue(Date.now.isToday)
    }

    func testIsTodayFalseForYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        XCTAssertFalse(yesterday.isToday)
    }

    func testIsYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        XCTAssertTrue(yesterday.isYesterday)
    }

    func testIsTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertTrue(tomorrow.isTomorrow)
    }

    func testIsInPast() {
        let pastDate = date(year: 2020, month: 1, day: 1)
        XCTAssertTrue(pastDate.isInPast)
    }

    func testIsInFuture() {
        let futureDate = date(year: 2099, month: 12, day: 31)
        XCTAssertTrue(futureDate.isInFuture)
    }

    // MARK: - Date Arithmetic

    func testAddingDays() {
        let start = date(year: 2025, month: 1, day: 28)
        let result = start.adding(days: 5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.day, 2)
        XCTAssertEqual(result?.month, 2)
    }

    func testAddingNegativeDays() {
        let start = date(year: 2025, month: 3, day: 1)
        let result = start.adding(days: -1)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.day, 28)
        XCTAssertEqual(result?.month, 2)
    }

    func testAddingHours() {
        let start = date(year: 2025, month: 1, day: 1, hour: 22)
        let result = start.adding(hours: 5)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.hour, 3)
        XCTAssertEqual(result?.day, 2)
    }

    func testAddingMonths() {
        let start = date(year: 2025, month: 11, day: 15)
        let result = start.adding(months: 3)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.month, 2)
        XCTAssertEqual(result?.year, 2026)
    }

    func testDaysUntil() {
        let start = date(year: 2025, month: 1, day: 1)
        let end = date(year: 2025, month: 1, day: 11)
        XCTAssertEqual(start.days(until: end), 10)
    }

    func testDaysUntilNegative() {
        let start = date(year: 2025, month: 1, day: 11)
        let end = date(year: 2025, month: 1, day: 1)
        XCTAssertEqual(start.days(until: end), -10)
    }

    // MARK: - Start / End of Day

    func testStartOfDay() {
        let d = date(year: 2025, month: 6, day: 15, hour: 14, minute: 30)
        let start = d.startOfDay
        XCTAssertEqual(start.hour, 0)
        XCTAssertEqual(start.minute, 0)
        XCTAssertEqual(start.day, 15)
    }

    func testEndOfDay() {
        let d = date(year: 2025, month: 6, day: 15, hour: 10)
        let end = d.endOfDay
        XCTAssertNotNil(end)
        XCTAssertEqual(end?.hour, 23)
        XCTAssertEqual(end?.minute, 59)
        XCTAssertEqual(end?.day, 15)
    }

    // MARK: - ISO 8601

    func testISO8601RoundTrip() {
        let original = date(year: 2025, month: 7, day: 4, hour: 12, minute: 30)
        let isoString = original.iso8601String
        let parsed = Date.fromISO8601(isoString)
        XCTAssertNotNil(parsed)
        // Allow 1 second tolerance for fractional-second rounding
        XCTAssertEqual(
            parsed!.timeIntervalSinceReferenceDate,
            original.timeIntervalSinceReferenceDate,
            accuracy: 1.0
        )
    }

    func testFromISO8601WithoutFractionalSeconds() {
        let parsed = Date.fromISO8601("2025-03-15T14:30:00Z")
        XCTAssertNotNil(parsed)
        // Verify it parsed the correct date in UTC
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: parsed!)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 15)
    }

    func testFromISO8601Invalid() {
        let parsed = Date.fromISO8601("not-a-date")
        XCTAssertNil(parsed)
    }

    // MARK: - Age Calculation

    func testYearsFromNow() {
        let birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        let age = birthDate.yearsFromNow
        XCTAssertNotNil(age)
        XCTAssertEqual(age, 30)
    }

    // MARK: - Relative String

    func testRelativeStringPast() {
        let now = Date.now
        let oneHourAgo = now.addingTimeInterval(-3600)
        let result = oneHourAgo.relativeString(to: now)
        // Should contain "ago" for a past date
        XCTAssertTrue(result.contains("ago"), "Expected relative string to contain 'ago', got: \(result)")
    }

    func testRelativeStringFuture() {
        let now = Date.now
        let oneHourLater = now.addingTimeInterval(3600)
        let result = oneHourLater.relativeString(to: now)
        // Should contain "in" for a future date
        XCTAssertTrue(result.contains("in"), "Expected relative string to contain 'in', got: \(result)")
    }
}
