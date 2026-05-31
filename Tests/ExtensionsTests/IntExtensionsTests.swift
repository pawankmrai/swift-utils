//
//  IntExtensionsTests.swift
//  SwiftUtils
//

import XCTest
@testable import SwiftUtilsExtensions

final class IntExtensionsTests: XCTestCase {

    // MARK: - Clamping

    func testClampedWithinRange() {
        XCTAssertEqual(50.clamped(to: 0...100), 50)
    }

    func testClampedAboveRange() {
        XCTAssertEqual(150.clamped(to: 0...100), 100)
    }

    func testClampedBelowRange() {
        XCTAssertEqual((-5).clamped(to: 0...100), 0)
    }

    // MARK: - Digit Helpers

    func testDigitCount() {
        XCTAssertEqual(0.digitCount, 1)
        XCTAssertEqual(5.digitCount, 1)
        XCTAssertEqual(42.digitCount, 2)
        XCTAssertEqual((-1234).digitCount, 4)
    }

    func testDigits() {
        XCTAssertEqual(0.digits, [0])
        XCTAssertEqual(123.digits, [1, 2, 3])
        XCTAssertEqual((-42).digits, [4, 2])
    }

    // MARK: - Ordinal

    func testOrdinal() {
        XCTAssertEqual(1.ordinal, "1st")
        XCTAssertEqual(2.ordinal, "2nd")
        XCTAssertEqual(3.ordinal, "3rd")
        XCTAssertEqual(4.ordinal, "4th")
        XCTAssertEqual(11.ordinal, "11th")
        XCTAssertEqual(22.ordinal, "22nd")
    }

    // MARK: - Roman Numerals

    func testRomanNumerals() {
        XCTAssertEqual(1.romanNumeral, "I")
        XCTAssertEqual(4.romanNumeral, "IV")
        XCTAssertEqual(9.romanNumeral, "IX")
        XCTAssertEqual(2024.romanNumeral, "MMXXIV")
        XCTAssertNil(0.romanNumeral)
        XCTAssertNil(4000.romanNumeral)
    }

    // MARK: - Time Intervals

    func testTimeIntervals() {
        XCTAssertEqual(5.seconds, 5.0)
        XCTAssertEqual(2.minutes, 120.0)
        XCTAssertEqual(1.hours, 3600.0)
        XCTAssertEqual(1.days, 86400.0)
    }

    // MARK: - Times

    func testTimes() {
        var count = 0
        3.times { _ in count += 1 }
        XCTAssertEqual(count, 3)
    }

    func testTimesWithZero() {
        var count = 0
        0.times { _ in count += 1 }
        XCTAssertEqual(count, 0)
    }

    func testTimesPassesIndex() {
        var indices: [Int] = []
        3.times { indices.append($0) }
        XCTAssertEqual(indices, [0, 1, 2])
    }

    // MARK: - Even / Odd

    func testEvenOdd() {
        XCTAssertTrue(4.isEven)
        XCTAssertFalse(4.isOdd)
        XCTAssertTrue(7.isOdd)
        XCTAssertFalse(7.isEven)
        XCTAssertTrue(0.isEven)
    }

    func testPositiveNegative() {
        XCTAssertTrue(5.isPositive)
        XCTAssertFalse(5.isNegative)
        XCTAssertTrue((-3).isNegative)
        XCTAssertFalse(0.isPositive)
        XCTAssertFalse(0.isNegative)
    }

    // MARK: - Byte Formatting

    func testFormattedBytes() {
        XCTAssertTrue(0.formattedBytes.contains("0"))
        XCTAssertTrue(1024.formattedBytes.contains("KB"))
    }

    // MARK: - Factorial

    func testFactorial() {
        XCTAssertEqual(0.factorial, 1)
        XCTAssertEqual(1.factorial, 1)
        XCTAssertEqual(5.factorial, 120)
        XCTAssertEqual(10.factorial, 3628800)
        XCTAssertNil((-1).factorial)
        XCTAssertNil(21.factorial)
    }

    // MARK: - Power

    func testPower() {
        XCTAssertEqual(2.power(10), 1024)
        XCTAssertEqual(3.power(0), 1)
        XCTAssertEqual(5.power(3), 125)
        XCTAssertEqual(2.power(-1), 0)
    }
}
