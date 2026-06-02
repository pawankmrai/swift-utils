# Collection+Extensions

Practical extensions on `Collection` for safe access, partitioning, aggregation, key-path operations, and inspection.

## API

| Method / Property | Description |
|---|---|
| `isNotEmpty` | Negation of `isEmpty` for cleaner conditionals |
| `[safe:]` | Returns `nil` for out-of-bounds indices |
| `nilIfEmpty` | Returns `nil` when the collection is empty |
| `onlyElement` | Returns the sole element, or `nil` if count ≠ 1 |
| `partitioned(by:)` | Splits into matching and non-matching arrays |
| `sum()` | Sum of `Numeric` elements |
| `average()` | Average as `Double` (integers) or `Element` (floats) |
| `sum(of:)` | Sum of a numeric key path |
| `average(of:)` | Average of a floating-point key path |
| `keyed(by:)` | Dictionary keyed by a `Hashable` key path |
| `allEqual()` | `true` if every element is the same (`Equatable`) |
| `count(of:)` | Number of occurrences of a value |
| `indices(where:)` | Indices of elements matching a predicate |

## Examples

```swift
import SwiftUtilsExtensions

// isNotEmpty — reads better than !isEmpty
let items = [1, 2, 3]
if items.isNotEmpty {
    print("Got \(items.count) items")
}

// Safe subscript on any Collection
let slice: ArraySlice = ["a", "b", "c"][1...]
slice[safe: 2]  // Optional("c")
slice[safe: 9]  // nil

// nilIfEmpty — great for optional chaining
let tags: [String] = []
let display = tags.nilIfEmpty ?? ["Untagged"]
// ["Untagged"]

// onlyElement
[42].onlyElement       // Optional(42)
[1, 2].onlyElement     // nil

// Partitioning
let numbers = [1, 2, 3, 4, 5, 6]
let (evens, odds) = numbers.partitioned { $0.isMultiple(of: 2) }
// evens: [2, 4, 6], odds: [1, 3, 5]

// Sum & average
[10, 20, 30].sum()       // 60
[10, 20, 30].average()   // Optional(20.0)

[1.5, 2.5, 3.0].sum()     // 7.0
[1.5, 2.5, 3.0].average() // Optional(2.333...)

// Key-path aggregation
struct LineItem { let name: String; let price: Double; let qty: Int }
let cart = [
    LineItem(name: "Widget", price: 9.99, qty: 3),
    LineItem(name: "Gadget", price: 24.99, qty: 1)
]
cart.sum(of: \.price)       // 34.98
cart.average(of: \.price)   // Optional(17.49)

// keyed(by:) — build a lookup dictionary
struct User { let id: Int; let name: String }
let users = [User(id: 1, name: "Alice"), User(id: 2, name: "Bob")]
let lookup = users.keyed(by: \.id)
lookup[1]?.name  // Optional("Alice")

// allEqual
[5, 5, 5].allEqual()    // true
[1, 2, 3].allEqual()    // false

// count(of:)
[1, 2, 1, 3, 1].count(of: 1)  // 3

// indices(where:)
[10, 20, 30, 40, 50].indices(where: { $0 > 25 })
// [2, 3, 4]
```
