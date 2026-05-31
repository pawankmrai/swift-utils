//
//  Int+Extensions.swift
//  SwiftUtils
//
//  Production-ready Int and BinaryInteger extensions
//  for common operations in iOS development.
//
//  Target: iOS 15+ / Swift 5.9+
//

import Foundation

// MARK: - Clamping

public extension Comparable {
    /// Clamps the value to the given closed range.
    ///
    ///     let rating = 150.clamped(to: 0...100) // 100
    ///     let temp = (-5).clamped(to: 0...50)    // 0
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Digit Helpers

public extension Int {
    /// The number of digits in the integer (ignoring sign).
    ///
    ///     42.digitCount      // 2
    ///     0.digitCount       // 1
    ///     (-1234).digitCount // 4
    var digitCount: Int {
        if self == 0 { return 1 }
        return Int(log10(Double(abs(self)))) + 1
    }

    /// Returns an array of individual digits (ignoring sign).
    ///
    ///     123.digits  // [1, 2, 3]
    ///     0.digits    // [0]
    var digits: [Int] {
        if self == 0 { return [0] }
        var result: [Int] = []
        var n = abs(self)
        while n > 0 {
            result.append(n % 10)
            n /= 10
        }
        return result.reversed()
    }
}

// MARK: - Ordinal String

public extension Int {
    /// Returns the ordinal string representation (e.g. "1st", "2nd", "3rd").
    ///
    ///     1.ordinal   // "1st"
    ///     22.ordinal  // "22nd"
    ///     113.ordinal // "113th"
    var ordinal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// MARK: - Roman Numerals

public extension Int {
    /// Converts a positive integer (1–3999) to a Roman numeral string.
    ///
    ///     4.romanNumeral    // "IV"
    ///     2024.romanNumeral // "MMXXIV"
    ///     0.romanNumeral    // nil
    var romanNumeral: String? {
        guard self > 0 && self < 4000 else { return nil }
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        var result = ""
        var remaining = self
        for (value, symbol) in zip(values, symbols) {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}

// MARK: - Time Intervals

public extension Int {
    /// Converts the integer to seconds as a `TimeInterval`.
    var seconds: TimeInterval { TimeInterval(self) }

    /// Converts the integer (as minutes) to seconds as a `TimeInterval`.
    var minutes: TimeInterval { TimeInterval(self * 60) }

    /// Converts the integer (as hours) to seconds as a `TimeInterval`.
    var hours: TimeInterval { TimeInterval(self * 3600) }

    /// Converts the integer (as days) to seconds as a `TimeInterval`.
    var days: TimeInterval { TimeInterval(self * 86400) }
}

// MARK: - Loop & Repeat

public extension Int {
    /// Executes a closure the given number of times, passing the iteration index.
    ///
    ///     3.times { i in print(i) } // 0, 1, 2
    func times(_ body: (Int) throws -> Void) rethrows {
        guard self > 0 else { return }
        for i in 0..<self {
            try body(i)
        }
    }
}

// MARK: - Even / Odd / Positive / Negative

public extension BinaryInteger {
    /// Whether the integer is even.
    var isEven: Bool { self % 2 == 0 }

    /// Whether the integer is odd.
    var isOdd: Bool { self % 2 != 0 }

    /// Whether the integer is strictly positive (> 0).
    var isPositive: Bool { self > 0 }

    /// Whether the integer is strictly negative (< 0).
    var isNegative: Bool { self < 0 }
}

// MARK: - Byte Formatting

public extension Int {
    /// Formats the integer as a human-readable byte string.
    ///
    ///     1024.formattedBytes            // "1 KB"
    ///     1_500_000.formattedBytes       // "1.4 MB"
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(self))
    }
}

// MARK: - Factorial & Power

public extension Int {
    /// Returns the factorial of a non-negative integer (up to 20).
    ///
    ///     5.factorial  // 120
    ///     0.factorial  // 1
    var factorial: Int? {
        guard self >= 0 && self <= 20 else { return nil }
        if self <= 1 { return 1 }
        return (2...self).reduce(1, *)
    }

    /// Returns self raised to the given power using repeated multiplication.
    ///
    ///     2.power(10)  // 1024
    ///     3.power(0)   // 1
    func power(_ exponent: Int) -> Int {
        guard exponent >= 0 else { return 0 }
        if exponent == 0 { return 1 }
        var result = 1
        for _ in 0..<exponent {
            result *= self
        }
        return result
    }
}
