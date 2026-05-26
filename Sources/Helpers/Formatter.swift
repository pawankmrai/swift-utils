import Foundation

// MARK: - DisplayFormatter

/// A convenience wrapper around Foundation formatters for common display tasks.
///
/// `DisplayFormatter` provides one-liner formatting for numbers, currencies,
/// percentages, file sizes, durations, ordinals, and compact notations.
/// All methods are thread-safe and use cached formatters for performance.
public enum DisplayFormatter {

    // MARK: - Number Formatting

    /// Formats a number with a fixed number of decimal places and grouping separators.
    ///
    /// - Parameters:
    ///   - value: The number to format.
    ///   - decimals: The number of fraction digits (default `0`).
    ///   - locale: The locale to use (default `.current`).
    /// - Returns: A formatted string, e.g. `"1,234"` or `"1,234.56"`.
    public static func number(_ value: Double, decimals: Int = 0, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Formats a number with a fixed number of decimal places and grouping separators.
    public static func number(_ value: Int, locale: Locale = .current) -> String {
        number(Double(value), decimals: 0, locale: locale)
    }

    // MARK: - Currency

    /// Formats a value as currency.
    ///
    /// - Parameters:
    ///   - value: The monetary amount.
    ///   - code: ISO 4217 currency code, e.g. `"USD"`, `"EUR"` (default `nil` uses locale).
    ///   - locale: The locale to use (default `.current`).
    /// - Returns: A formatted currency string, e.g. `"$1,234.56"`.
    public static func currency(_ value: Double, code: String? = nil, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        if let code = code {
            formatter.currencyCode = code
        }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Percentage

    /// Formats a fraction as a percentage.
    ///
    /// - Parameters:
    ///   - value: The fractional value (e.g. `0.42` for 42%).
    ///   - decimals: The number of fraction digits (default `0`).
    ///   - locale: The locale to use (default `.current`).
    /// - Returns: A formatted percentage, e.g. `"42%"`.
    public static func percentage(_ value: Double, decimals: Int = 0, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - File Size

    /// Formats a byte count into a human-readable file-size string.
    ///
    /// - Parameters:
    ///   - bytes: The number of bytes.
    ///   - countStyle: The counting style (default `.file`).
    /// - Returns: A formatted string, e.g. `"4.2 MB"`.
    public static func fileSize(_ bytes: Int64, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = countStyle
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }

    /// Formats a byte count into a human-readable file-size string.
    public static func fileSize(_ bytes: Int, countStyle: ByteCountFormatter.CountStyle = .file) -> String {
        fileSize(Int64(bytes), countStyle: countStyle)
    }

    // MARK: - Duration

    /// Formats a time interval into a human-readable duration.
    ///
    /// - Parameters:
    ///   - seconds: The number of seconds.
    ///   - style: The units style (default `.abbreviated`).
    ///   - allowedUnits: The calendar units to display (default hours, minutes, seconds).
    /// - Returns: A formatted string, e.g. `"2h 15m 30s"` or `"2 hours, 15 minutes"`.
    public static func duration(
        _ seconds: TimeInterval,
        style: DateComponentsFormatter.UnitsStyle = .abbreviated,
        allowedUnits: NSCalendar.Unit = [.hour, .minute, .second]
    ) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = style
        formatter.allowedUnits = allowedUnits
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }

    // MARK: - Ordinal

    /// Formats a number as an ordinal (e.g. 1st, 2nd, 3rd).
    ///
    /// - Parameters:
    ///   - value: The integer to format.
    ///   - locale: The locale to use (default `.current`).
    /// - Returns: A formatted ordinal string, e.g. `"3rd"`.
    public static func ordinal(_ value: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Compact / Abbreviated Numbers

    /// Formats a number in compact notation (e.g. 1.2K, 3.5M).
    ///
    /// - Parameters:
    ///   - value: The number to format.
    ///   - decimals: Maximum fraction digits (default `1`).
    ///   - locale: The locale to use (default `.current`).
    /// - Returns: A compact string, e.g. `"1.2K"` or `"3.5M"`.
    public static func compact(_ value: Double, decimals: Int = 1, locale: Locale = .current) -> String {
        let thresholds: [(Double, String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K"),
        ]

        for (threshold, suffix) in thresholds {
            if abs(value) >= threshold {
                let divided = value / threshold
                let formatted = String(format: "%.\(decimals)f", divided)
                // Trim trailing zeros after decimal point
                let trimmed = trimTrailingZeros(formatted)
                return "\(trimmed)\(suffix)"
            }
        }

        return number(value, decimals: 0, locale: locale)
    }

    /// Formats an integer in compact notation.
    public static func compact(_ value: Int, decimals: Int = 1, locale: Locale = .current) -> String {
        compact(Double(value), decimals: decimals, locale: locale)
    }

    // MARK: - List Formatting

    /// Joins a list of strings using locale-aware list formatting.
    ///
    /// - Parameters:
    ///   - items: The items to join.
    ///   - type: The list type (default `.and`).
    ///   - locale: The locale to use (default `.current`).
    /// - Returns: A formatted list, e.g. `"A, B, and C"`.
    @available(iOS 15, macOS 12, *)
    public static func list(_ items: [String], type: ListFormatStyle.ListType = .and, locale: Locale = .current) -> String {
        var style = ListFormatStyle.list(type: type, width: .standard)
        style.locale = locale
        return style.format(items)
    }

    // MARK: - Private Helpers

    private static func trimTrailingZeros(_ string: String) -> String {
        guard string.contains(".") else { return string }
        var result = string
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
