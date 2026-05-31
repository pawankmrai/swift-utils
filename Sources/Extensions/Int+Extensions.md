# Int+Extensions

Integer utilities for clamping, digit inspection, ordinals, Roman numerals, time intervals, looping, parity checks, byte formatting, and math helpers.

## API

| Method / Property | Description |
|---|---|
| `clamped(to:)` | Clamp any `Comparable` value to a closed range |
| `digitCount` | Number of digits (ignoring sign) |
| `digits` | Array of individual digits |
| `ordinal` | Locale-aware ordinal string ("1st", "2nd", …) |
| `romanNumeral` | Roman numeral string (1–3999) or nil |
| `seconds` | Int → `TimeInterval` in seconds |
| `minutes` | Int → `TimeInterval` in seconds (×60) |
| `hours` | Int → `TimeInterval` in seconds (×3600) |
| `days` | Int → `TimeInterval` in seconds (×86400) |
| `times(_:)` | Execute a closure N times with iteration index |
| `isEven` | Whether the integer is even |
| `isOdd` | Whether the integer is odd |
| `isPositive` | Whether > 0 |
| `isNegative` | Whether < 0 |
| `formattedBytes` | Human-readable byte string ("1.4 MB") |
| `factorial` | Factorial for 0–20, nil otherwise |
| `power(_:)` | Integer exponentiation |

## Examples

### Clamping Values

```swift
let volume = userInput.clamped(to: 0...100)
let progress = rawValue.clamped(to: 0.0...1.0)
```

### Digit Inspection

```swift
let pin = 1234
print(pin.digitCount) // 4
print(pin.digits)     // [1, 2, 3, 4]
```

### Ordinal Strings

```swift
let position = 3
print("You finished \(position.ordinal)!") // "You finished 3rd!"

// Works with larger numbers
print(112.ordinal) // "112th"
print(21.ordinal)  // "21st"
```

### Roman Numerals

```swift
let year = 2024
print(year.romanNumeral!) // "MMXXIV"

let chapter = 14
print("Chapter \(chapter.romanNumeral!)") // "Chapter XIV"
```

### Time Intervals

```swift
// Use with Timer, DispatchQueue, or animation
Timer.scheduledTimer(withTimeInterval: 30.seconds, repeats: true) { _ in
    refreshData()
}

UIView.animate(withDuration: 0.3.seconds) { view.alpha = 1 }

// Schedule background tasks
let cacheExpiry = 2.hours
let sessionTimeout = 30.minutes
```

### Looping

```swift
// Repeat an action
5.times { index in
    print("Attempt \(index + 1)")
}

// Generate test data
var items: [String] = []
10.times { i in items.append("Item \(i)") }
```

### Parity and Sign Checks

```swift
let numbers = [1, 2, 3, 4, 5, 6]
let evens = numbers.filter(\.isEven)   // [2, 4, 6]
let odds = numbers.filter(\.isOdd)     // [1, 3, 5]

if score.isPositive { showReward() }
```

### Byte Formatting

```swift
let fileSize = 1_573_000
print(fileSize.formattedBytes) // "1.5 MB"

let downloaded = 512
print(downloaded.formattedBytes) // "512 bytes"
```

### Math Helpers

```swift
print(5.factorial!)  // 120
print(2.power(10))   // 1024
print(3.power(4))    // 81
```
