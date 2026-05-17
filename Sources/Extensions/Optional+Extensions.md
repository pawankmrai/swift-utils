# Optional+Extensions

Ergonomic helpers for unwrapping, chaining, filtering, zipping, and providing defaults for Swift optionals — with specialized extensions for String, Collection, Numeric, and Bool.

## API

| Method / Property | Description |
|---|---|
| `orThrow(_:)` | Unwrap or throw an error |
| `or(_:)` | Unwrap or return a default (clearer `??` alternative) |
| `orAsync(_:)` | Unwrap or await an async fallback |
| `ifLet(_:)` | Execute a closure if non-nil, returns self for chaining |
| `ifNil(_:)` | Execute a closure if nil, returns self for chaining |
| `isNil` | `true` when the optional is `nil` |
| `isNotNil` | `true` when the optional contains a value |
| `filter(_:)` | Keep value only if predicate passes |
| `flatMapNil(_:)` | Transform with a failable closure |
| `zip(_:)` | Combine two optionals into a tuple |
| `zip(_:_:)` | Combine three optionals into a tuple |
| **Collection** | |
| `isNilOrEmpty` | `true` if nil or empty collection |
| `nilIfEmpty` | Returns nil for empty collections |
| **String** | |
| `isNilOrBlank` | `true` if nil, empty, or whitespace-only |
| `nilIfBlank` | Returns nil for blank strings |
| `orEmpty` | Returns the string or `""` |
| **Numeric** | |
| `orZero` | Returns the number or `0` |
| **Bool** | |
| `orFalse` | Returns the bool or `false` |
| `orTrue` | Returns the bool or `true` |

## Examples

```swift
import SwiftUtilsExtensions

// Convert optional to throwing expression
struct AppError: Error { case missingData }
let data: Data? = fetchData()
let unwrapped = try data.orThrow(AppError.missingData)

// Chainable side-effects
let cachedUser: User? = cache.get("user")
cachedUser
    .ifLet { analytics.track("cache_hit", user: $0) }
    .ifNil { analytics.track("cache_miss") }

// Filter an optional by a condition
let age: Int? = 16
let adultAge = age.filter { $0 >= 18 }  // nil

// Zip optionals together for safe destructuring
let name: String? = "Pawan"
let email: String? = "pawan@example.com"
if let (n, e) = name.zip(email) {
    createAccount(name: n, email: e)
}

// Three-way zip
let firstName: String? = "Jane"
let lastName: String? = "Doe"
let dept: String? = "Engineering"
if let (f, l, d) = firstName.zip(lastName, dept) {
    print("\(f) \(l) — \(d)")
}

// Collection helpers
let tags: [String]? = []
tags.isNilOrEmpty      // true

let results: [Int]? = [1, 2, 3]
guard let items = results.nilIfEmpty else { return }
// items is guaranteed non-empty

// String helpers
let input: String? = "   "
input.isNilOrBlank     // true
input.nilIfBlank       // nil

let title: String? = nil
label.text = title.orEmpty  // ""

// Numeric helpers
let score: Int? = nil
let total = score.orZero + 10  // 10

// Bool helpers
let isEnabled: Bool? = nil
if isEnabled.orFalse {
    enableFeature()
}
```
