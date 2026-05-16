# Validator

A composable, type-safe input validation framework with chainable rules.

## API

| Type / Method | Description |
|---|---|
| `Validator<Value>` | Aggregates rules for a given type |
| `.add(_:)` | Chain a validation rule |
| `.validate(_:)` | Returns `.valid` or first `.invalid` |
| `.errors(for:)` | Returns all failure reasons |
| `.firstError(for:)` | Returns first failure reason or nil |

### Built-in Rules for `String`

| Rule | Description |
|---|---|
| `.nonEmpty(message:)` | Rejects empty / whitespace-only strings |
| `.email()` | Validates email format |
| `.minLength(_:)` | Minimum character count |
| `.maxLength(_:)` | Maximum character count |
| `.strongPassword()` | Upper, lower, digit, 8+ chars |
| `.pattern(_:name:message:)` | Custom regex |

## Examples

```swift
import SwiftUtilsHelpers

// Email validation
let emailValidator = Validator<String>()
    .add(.nonEmpty(message: "Email is required"))
    .add(.email())

emailValidator.errors(for: "")
// ["Email is required", "Value is not a valid email address"]

emailValidator.errors(for: "user@example.com")
// [] (empty — valid)

// Password validation
let passwordValidator = Validator<String>()
    .add(.minLength(8))
    .add(.strongPassword())

if let error = passwordValidator.firstError(for: "weak") {
    showError(error)  // "Must be at least 8 characters"
}

// Custom rule
let usernameValidator = Validator<String>()
    .add(.nonEmpty())
    .add(.minLength(3))
    .add(.maxLength(20))
    .add(ValidationRule(name: "alphanumeric") { value in
        value.allSatisfy { $0.isLetter || $0.isNumber }
            ? .valid
            : .invalid(reason: "Only letters and numbers allowed")
    })

// Comparable range validation
let ageValidator = Validator<Int>()
    .add(.range(18...120, message: "Must be between 18 and 120"))
```
