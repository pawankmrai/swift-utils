# String+Extensions

Common string helpers for everyday iOS development.

## API

| Property / Method | Returns | Description |
|---|---|---|
| `isValidEmail` | `Bool` | Checks email format via regex |
| `trimmed` | `String` | Strips leading/trailing whitespace |
| `isNumeric` | `Bool` | `true` if string contains only digits |
| `truncated(to:trailing:)` | `String` | Cuts to length, appends trailing string |
| `slugified` | `String` | URL-safe lowercase slug |
| `snakeCased` | `String` | Converts camelCase to snake_case |

## Examples

```swift
import SwiftUtilsExtensions

// Email validation
"user@example.com".isValidEmail  // true
"not-an-email".isValidEmail      // false

// Trimming
"  hello world  ".trimmed  // "hello world"

// Numeric check
"12345".isNumeric  // true
"123a5".isNumeric  // false

// Truncation
"A very long title that should be shorter".truncated(to: 20)
// "A very long title th…"

"Hello World".truncated(to: 5, trailing: "...")
// "Hello..."

// Slugification
"Hello World From Swift!".slugified  // "hello-world-from-swift"

// Snake case conversion
"backgroundColor".snakeCased  // "background_color"
"userProfileURL".snakeCased   // "user_profile_url"
```
