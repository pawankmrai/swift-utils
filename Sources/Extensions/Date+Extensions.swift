import Foundation

// MARK: - Date Extensions

/// A collection of production-ready `Date` utilities for iOS applications.
/// Covers relative formatting, component access, comparisons, and common
/// date arithmetic used in everyday app development.
extension Date {

    // MARK: - Relative Formatting

    /// Returns a human-readable relative time string (e.g. "2 hours ago", "in 3 days").
    ///
    /// Uses `RelativeDateTimeFormatter` under the hood for proper localization.
    ///
    /// - Parameter date: The reference date to compare against. Defaults to `.now`.
    /// - Returns: A localized relative time string.
    public func relativeString(to date: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: date)
    }

    /// Formats the date using a custom format string.
    ///
    /// - Parameters:
    ///   - format: A date format pattern (e.g. `"yyyy-MM-dd"`, `"MMM d, yyyy"`).
    ///   - locale: The locale to use. Defaults to the current locale.
    ///   - timeZone: The time zone to use. Defaults to the current time zone.
    /// - Returns: A formatted date string.
    public func formatted(
        as format: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = locale
        formatter.timeZone = timeZone
        return formatter.string(from: self)
    }

    // MARK: - Component Access

    /// The year component of this date in the current calendar.
    public var year: Int {
        Calendar.current.component(.year, from: self)
    }

    /// The month component (1–12) of this date in the current calendar.
    public var month: Int {
        Calendar.current.component(.month, from: self)
    }

    /// The day-of-month component of this date in the current calendar.
    public var day: Int {
        Calendar.current.component(.day, from: self)
    }

    /// The hour component (0–23) of this date in the current calendar.
    public var hour: Int {
        Calendar.current.component(.hour, from: self)
    }

    /// The minute component of this date in the current calendar.
    public var minute: Int {
        Calendar.current.component(.minute, from: self)
    }

    // MARK: - Day Comparisons

    /// Whether this date falls on the same calendar day as the given date.
    ///
    /// - Parameter other: The date to compare against.
    /// - Returns: `true` if both dates share the same year, month, and day.
    public func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// Whether this date is today in the current calendar.
    public var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Whether this date is yesterday in the current calendar.
    public var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Whether this date is tomorrow in the current calendar.
    public var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    /// Whether this date falls on a weekend day in the current calendar.
    public var isWeekend: Bool {
        Calendar.current.isDateInWeekend(self)
    }

    /// Whether this date is in the past relative to now.
    public var isInPast: Bool {
        self < Date.now
    }

    /// Whether this date is in the future relative to now.
    public var isInFuture: Bool {
        self > Date.now
    }

    // MARK: - Date Arithmetic

    /// Returns a new date by adding the specified number of days.
    ///
    /// - Parameter days: The number of days to add (negative values subtract).
    /// - Returns: A new `Date`, or `nil` if the calculation overflows.
    public func adding(days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: self)
    }

    /// Returns a new date by adding the specified number of hours.
    ///
    /// - Parameter hours: The number of hours to add (negative values subtract).
    /// - Returns: A new `Date`, or `nil` if the calculation overflows.
    public func adding(hours: Int) -> Date? {
        Calendar.current.date(byAdding: .hour, value: hours, to: self)
    }

    /// Returns a new date by adding the specified number of months.
    ///
    /// - Parameter months: The number of months to add (negative values subtract).
    /// - Returns: A new `Date`, or `nil` if the calculation overflows.
    public func adding(months: Int) -> Date? {
        Calendar.current.date(byAdding: .month, value: months, to: self)
    }

    /// The number of calendar days between this date and another date.
    ///
    /// A positive value means `other` is in the future relative to `self`.
    ///
    /// - Parameter other: The target date.
    /// - Returns: The signed number of days, or `nil` if the calculation fails.
    public func days(until other: Date) -> Int? {
        Calendar.current.dateComponents([.day], from: self, to: other).day
    }

    // MARK: - Start / End of Day

    /// The start of the calendar day (midnight) for this date.
    public var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// The last moment of the calendar day (23:59:59) for this date.
    public var endOfDay: Date? {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay)
    }

    // MARK: - ISO 8601

    /// Returns the date formatted as an ISO 8601 string with fractional seconds.
    ///
    /// Example output: `"2024-03-15T14:30:00.000Z"`
    public var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    /// Creates a date from an ISO 8601 string.
    ///
    /// - Parameter string: An ISO 8601 formatted date string.
    /// - Returns: A `Date` if parsing succeeds, otherwise `nil`.
    public static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        // Retry without fractional seconds for broader compatibility
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Age Calculation

    /// Calculates the number of full years between this date and now.
    ///
    /// Useful for computing a person's age from their birth date.
    ///
    /// - Returns: The number of completed years, or `nil` if the calculation fails.
    public var yearsFromNow: Int? {
        Calendar.current.dateComponents([.year], from: self, to: .now).year
    }
}
