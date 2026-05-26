# DisplayFormatter

A lightweight, zero-configuration formatting toolkit for common display tasks in iOS apps. Wraps Foundation formatters behind a simple enum API for numbers, currencies, percentages, file sizes, durations, ordinals, compact notation, and locale-aware lists.

## API

| Type / Method | Description |
|---|---|
| `DisplayFormatter.number(_:decimals:locale:)` | Format a `Double` with grouping separators and fixed decimals |
| `DisplayFormatter.number(_:locale:)` | Format an `Int` with grouping separators |
| `DisplayFormatter.currency(_:code:locale:)` | Format a value as currency (auto or explicit ISO 4217 code) |
| `DisplayFormatter.percentage(_:decimals:locale:)` | Format a fraction (0.0–1.0) as a percentage |
| `DisplayFormatter.fileSize(_:countStyle:)` | Format bytes as a human-readable file size (KB, MB, GB…) |
| `DisplayFormatter.duration(_:style:allowedUnits:)` | Format seconds into hours/minutes/seconds display |
| `DisplayFormatter.ordinal(_:locale:)` | Format an integer as an ordinal (1st, 2nd, 3rd…) |
| `DisplayFormatter.compact(_:decimals:locale:)` | Format large numbers in compact notation (1.2K, 3.5M…) |
| `DisplayFormatter.list(_:type:locale:)` | Join strings with locale-aware list formatting ("A, B, and C") |

### Duration Styles

| Style | Example |
|---|---|
| `.abbreviated` | `2h 15m 30s` |
| `.short` | `2 hr, 15 min` |
| `.full` | `2 hours, 15 minutes, 30 seconds` |
| `.brief` | `2hr 15min` |
| `.spellOut` | `two hours, fifteen minutes` |

### File Size Count Styles

| Style | Description |
|---|---|
| `.file` | Actual file size (base-10, 1 MB = 1,000,000 bytes) |
| `.memory` | Memory size (base-2, 1 MB = 1,048,576 bytes) |
| `.decimal` | Base-10 display |
| `.binary` | Base-2 display |

## Examples

```swift
import SwiftUtilsHelpers

// Number formatting
DisplayFormatter.number(1234567.0)              // "1,234,567"
DisplayFormatter.number(1234567.891, decimals: 2) // "1,234,567.89"
DisplayFormatter.number(42)                      // "42"

// Currency
DisplayFormatter.currency(1234.56)               // "$1,234.56" (locale-dependent)
DisplayFormatter.currency(1234.56, code: "EUR")  // "€1,234.56"
DisplayFormatter.currency(99.9, code: "GBP")     // "£99.90"

// Percentage
DisplayFormatter.percentage(0.42)                // "42%"
DisplayFormatter.percentage(0.8567, decimals: 1) // "85.7%"
DisplayFormatter.percentage(1.0)                 // "100%"

// File sizes
DisplayFormatter.fileSize(1024)                  // "1 KB"
DisplayFormatter.fileSize(Int64(5_400_000))      // "5.4 MB"
DisplayFormatter.fileSize(Int64(2_000_000_000))  // "2 GB"

// Duration
DisplayFormatter.duration(3661)                  // "1h 1m 1s"
DisplayFormatter.duration(7200, style: .full)    // "2 hours"
DisplayFormatter.duration(90, allowedUnits: [.minute, .second]) // "1m 30s"
DisplayFormatter.duration(45)                    // "45s"

// Ordinals
DisplayFormatter.ordinal(1)                      // "1st"
DisplayFormatter.ordinal(2)                      // "2nd"
DisplayFormatter.ordinal(3)                      // "3rd"
DisplayFormatter.ordinal(11)                     // "11th"
DisplayFormatter.ordinal(42)                     // "42nd"

// Compact numbers
DisplayFormatter.compact(1_500)                  // "1.5K"
DisplayFormatter.compact(2_300_000)              // "2.3M"
DisplayFormatter.compact(7_800_000_000)          // "7.8B"
DisplayFormatter.compact(500)                    // "500"
DisplayFormatter.compact(-45_000)                // "-45K"

// List formatting (iOS 15+)
DisplayFormatter.list(["Alice", "Bob", "Charlie"])         // "Alice, Bob, and Charlie"
DisplayFormatter.list(["Red", "Blue"], type: .or)          // "Red or Blue"
DisplayFormatter.list(["Swift"])                            // "Swift"

// Real-world usage in a SwiftUI view
struct StatsView: View {
    let followers: Int
    let revenue: Double
    let uploadSize: Int64
    let watchTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(DisplayFormatter.compact(followers)) followers")
            Text(DisplayFormatter.currency(revenue))
            Text("\(DisplayFormatter.fileSize(uploadSize)) uploaded")
            Text("\(DisplayFormatter.duration(watchTime)) watched")
        }
    }
}

// Formatting a leaderboard
let players = ["Alice": 1, "Bob": 2, "Charlie": 3]
for (name, rank) in players {
    print("\(DisplayFormatter.ordinal(rank)) place: \(name)")
    // "1st place: Alice", "2nd place: Bob", "3rd place: Charlie"
}
```
