# Date+Extensions

Relative formatting, component access, date arithmetic, ISO 8601, and day-level comparisons.

## API

| Property / Method | Description |
|---|---|
| `relativeString(to:)` | Human-readable relative time ("2 hours ago") |
| `formatted(as:locale:timeZone:)` | Custom format string |
| `year`, `month`, `day`, `hour`, `minute` | Calendar component accessors |
| `isToday`, `isYesterday`, `isTomorrow` | Day-level checks |
| `isWeekend`, `isInPast`, `isInFuture` | Additional comparisons |
| `isSameDay(as:)` | Compare two dates at day granularity |
| `adding(days:)`, `adding(hours:)`, `adding(months:)` | Date arithmetic |
| `days(until:)` | Signed day count between dates |
| `startOfDay`, `endOfDay` | Midnight / 23:59:59 boundaries |
| `iso8601String` | Format as ISO 8601 |
| `Date.fromISO8601(_:)` | Parse ISO 8601 string |
| `yearsFromNow` | Full years since this date (age calculation) |

## Examples

```swift
import SwiftUtilsExtensions

// Relative formatting
let yesterday = Date().adding(days: -1)!
yesterday.relativeString()  // "1 day ago"

// Custom formatting
Date().formatted(as: "MMM d, yyyy")  // "May 16, 2026"
Date().formatted(as: "HH:mm")       // "14:30"

// Component access
let now = Date()
print(now.year)   // 2026
print(now.month)  // 5
print(now.day)    // 16

// Day comparisons
Date().isToday     // true
Date().isWeekend   // true/false depending on day

// Date arithmetic
let nextWeek = Date().adding(days: 7)!
let threeMonthsLater = Date().adding(months: 3)!
Date().days(until: nextWeek)!  // 7

// Start/end of day
let midnight = Date().startOfDay
let endOfDay = Date().endOfDay!

// ISO 8601
Date().iso8601String  // "2026-05-16T14:30:00.000Z"
let parsed = Date.fromISO8601("2026-01-15T10:00:00Z")

// Age calculation
let birthDate = Date.fromISO8601("1995-06-20T00:00:00Z")!
birthDate.yearsFromNow  // 30
```
