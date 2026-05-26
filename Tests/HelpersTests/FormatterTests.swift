import XCTest
@testable import SwiftUtilsHelpers

final class DisplayFormatterTests: XCTestCase {

    private let usLocale = Locale(identifier: "en_US")

    // MARK: - Number

    func testNumberFormatsWithGroupingSeparators() {
        let result = DisplayFormatter.number(1_234_567.0, locale: usLocale)
        XCTAssertEqual(result, "1,234,567")
    }

    func testNumberFormatsWithDecimals() {
        let result = DisplayFormatter.number(1234.567, decimals: 2, locale: usLocale)
        XCTAssertEqual(result, "1,234.57")
    }

    func testNumberFormatsZeroDecimals() {
        let result = DisplayFormatter.number(99.9, decimals: 0, locale: usLocale)
        XCTAssertEqual(result, "100")
    }

    func testNumberFormatsInteger() {
        let result = DisplayFormatter.number(42, locale: usLocale)
        XCTAssertEqual(result, "42")
    }

    func testNumberFormatsLargeInteger() {
        let result = DisplayFormatter.number(1_000_000, locale: usLocale)
        XCTAssertEqual(result, "1,000,000")
    }

    // MARK: - Currency

    func testCurrencyFormatsUSD() {
        let result = DisplayFormatter.currency(1234.56, code: "USD", locale: usLocale)
        XCTAssertEqual(result, "$1,234.56")
    }

    func testCurrencyFormatsSmallAmount() {
        let result = DisplayFormatter.currency(0.99, code: "USD", locale: usLocale)
        XCTAssertEqual(result, "$0.99")
    }

    func testCurrencyFormatsZero() {
        let result = DisplayFormatter.currency(0, code: "USD", locale: usLocale)
        XCTAssertEqual(result, "$0.00")
    }

    func testCurrencyFormatsNegative() {
        let result = DisplayFormatter.currency(-50.0, code: "USD", locale: usLocale)
        XCTAssertTrue(result.contains("50.00"))
    }

    // MARK: - Percentage

    func testPercentageFormatsBasic() {
        let result = DisplayFormatter.percentage(0.42, locale: usLocale)
        XCTAssertEqual(result, "42%")
    }

    func testPercentageFormatsWithDecimals() {
        let result = DisplayFormatter.percentage(0.8567, decimals: 1, locale: usLocale)
        XCTAssertEqual(result, "85.7%")
    }

    func testPercentageFormatsZero() {
        let result = DisplayFormatter.percentage(0.0, locale: usLocale)
        XCTAssertEqual(result, "0%")
    }

    func testPercentageFormatsOne() {
        let result = DisplayFormatter.percentage(1.0, locale: usLocale)
        XCTAssertEqual(result, "100%")
    }

    func testPercentageFormatsOver100() {
        let result = DisplayFormatter.percentage(1.5, locale: usLocale)
        XCTAssertEqual(result, "150%")
    }

    // MARK: - File Size

    func testFileSizeFormatsBytes() {
        let result = DisplayFormatter.fileSize(500)
        XCTAssertTrue(result.contains("500") || result.contains("bytes") || result.contains("B"))
    }

    func testFileSizeFormatsKilobytes() {
        let result = DisplayFormatter.fileSize(Int64(1024))
        XCTAssertTrue(result.contains("K") || result.contains("KB"))
    }

    func testFileSizeFormatsMegabytes() {
        let result = DisplayFormatter.fileSize(Int64(5_400_000))
        XCTAssertTrue(result.contains("M") || result.contains("MB"))
    }

    func testFileSizeFormatsGigabytes() {
        let result = DisplayFormatter.fileSize(Int64(2_000_000_000))
        XCTAssertTrue(result.contains("G") || result.contains("GB"))
    }

    func testFileSizeFormatsZero() {
        let result = DisplayFormatter.fileSize(0)
        XCTAssertTrue(result.contains("0") || result.contains("Zero"))
    }

    // MARK: - Duration

    func testDurationFormatsSeconds() {
        let result = DisplayFormatter.duration(45)
        XCTAssertTrue(result.contains("45"))
    }

    func testDurationFormatsMinutesAndSeconds() {
        let result = DisplayFormatter.duration(90, allowedUnits: [.minute, .second])
        XCTAssertTrue(result.contains("1") && result.contains("30"))
    }

    func testDurationFormatsHours() {
        let result = DisplayFormatter.duration(7200)
        XCTAssertTrue(result.contains("2"))
    }

    func testDurationFormatsZero() {
        let result = DisplayFormatter.duration(0)
        XCTAssertTrue(result.contains("0") || result.isEmpty == false)
    }

    // MARK: - Ordinal

    func testOrdinalFirst() {
        let result = DisplayFormatter.ordinal(1, locale: usLocale)
        XCTAssertEqual(result, "1st")
    }

    func testOrdinalSecond() {
        let result = DisplayFormatter.ordinal(2, locale: usLocale)
        XCTAssertEqual(result, "2nd")
    }

    func testOrdinalThird() {
        let result = DisplayFormatter.ordinal(3, locale: usLocale)
        XCTAssertEqual(result, "3rd")
    }

    func testOrdinalEleventh() {
        let result = DisplayFormatter.ordinal(11, locale: usLocale)
        XCTAssertEqual(result, "11th")
    }

    func testOrdinalTwentyFirst() {
        let result = DisplayFormatter.ordinal(21, locale: usLocale)
        XCTAssertEqual(result, "21st")
    }

    // MARK: - Compact

    func testCompactFormatsThousands() {
        let result = DisplayFormatter.compact(1_500)
        XCTAssertEqual(result, "1.5K")
    }

    func testCompactFormatsMillions() {
        let result = DisplayFormatter.compact(2_300_000)
        XCTAssertEqual(result, "2.3M")
    }

    func testCompactFormatsBillions() {
        let result = DisplayFormatter.compact(7_800_000_000.0)
        XCTAssertEqual(result, "7.8B")
    }

    func testCompactFormatsTrillions() {
        let result = DisplayFormatter.compact(1_500_000_000_000.0)
        XCTAssertEqual(result, "1.5T")
    }

    func testCompactFormatsBelowThreshold() {
        let result = DisplayFormatter.compact(500)
        XCTAssertEqual(result, "500")
    }

    func testCompactFormatsExactThousand() {
        let result = DisplayFormatter.compact(1_000)
        XCTAssertEqual(result, "1K")
    }

    func testCompactFormatsNegative() {
        let result = DisplayFormatter.compact(-45_000.0)
        XCTAssertEqual(result, "-45K")
    }

    func testCompactFormatsWithCustomDecimals() {
        let result = DisplayFormatter.compact(1_234_567.0, decimals: 2)
        XCTAssertEqual(result, "1.23M")
    }

    // MARK: - List

    @available(iOS 15, macOS 12, *)
    func testListFormatsMultipleItems() {
        let result = DisplayFormatter.list(["Alice", "Bob", "Charlie"], locale: usLocale)
        XCTAssertEqual(result, "Alice, Bob, and Charlie")
    }

    @available(iOS 15, macOS 12, *)
    func testListFormatsSingleItem() {
        let result = DisplayFormatter.list(["Swift"], locale: usLocale)
        XCTAssertEqual(result, "Swift")
    }

    @available(iOS 15, macOS 12, *)
    func testListFormatsTwoItems() {
        let result = DisplayFormatter.list(["Red", "Blue"], locale: usLocale)
        XCTAssertEqual(result, "Red and Blue")
    }

    @available(iOS 15, macOS 12, *)
    func testListFormatsOrType() {
        let result = DisplayFormatter.list(["Red", "Blue"], type: .or, locale: usLocale)
        XCTAssertEqual(result, "Red or Blue")
    }

    // MARK: - Trim Trailing Zeros (via compact)

    func testCompactTrimsTrailingZeros() {
        // 2,000,000 / 1,000,000 = 2.0 → should be "2M" not "2.0M"
        let result = DisplayFormatter.compact(2_000_000)
        XCTAssertEqual(result, "2M")
    }
}
