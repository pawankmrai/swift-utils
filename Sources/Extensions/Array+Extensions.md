# Array+Extensions

Safe subscripting, chunking, deduplication, grouping, frequency counting, key-path sorting, and more.

## API

| Method | Description |
|---|---|
| `[safe:]` | Returns `nil` instead of crashing on out-of-bounds |
| `chunked(into:)` | Splits array into sub-arrays of given size |
| `uniqued()` | Removes duplicates preserving order (Equatable) |
| `uniquedFast()` | O(n) dedup using Set (Hashable) |
| `uniqued(by:)` | Dedup by key path |
| `grouped(by:)` | Groups elements by key path into a dictionary |
| `frequencies()` | Counts occurrences of each element |
| `min(by:)` / `max(by:)` | Min/max element by key path |
| `sorted(by:ascending:)` | Sort by key path |
| `compactMap(unwrapping:)` | Extract non-nil values at a key path |
| `appendIfAbsent(_:)` | Append only if not already present |

## Examples

```swift
import SwiftUtilsExtensions

// Safe subscript — no more "index out of range" crashes
let items = ["a", "b", "c"]
items[safe: 1]   // Optional("b")
items[safe: 99]  // nil

// Chunking
[1, 2, 3, 4, 5].chunked(into: 2)
// [[1, 2], [3, 4], [5]]

// Deduplication
[1, 2, 3, 2, 1, 4].uniqued()       // [1, 2, 3, 4]
["a", "b", "a"].uniquedFast()       // ["a", "b"]

// Dedup by key path
struct User { let id: Int; let name: String }
let users = [User(id: 1, name: "A"), User(id: 2, name: "B"), User(id: 1, name: "C")]
users.uniqued(by: \.id)  // keeps first occurrence per id

// Grouping
struct Task { let priority: String; let title: String }
let tasks = [Task(priority: "high", title: "Fix crash"),
             Task(priority: "low", title: "Update docs")]
tasks.grouped(by: \.priority)
// ["high": [Task(...)], "low": [Task(...)]]

// Frequency counting
["a", "b", "a", "c", "a"].frequencies()
// ["a": 3, "b": 1, "c": 1]

// Sorting by key path
struct Product { let name: String; let price: Double }
let products = [Product(name: "B", price: 29.99), Product(name: "A", price: 9.99)]
products.sorted(by: \.price)            // ascending by price
products.min(by: \.price)               // cheapest product

// Conditional append
var tags = ["swift", "ios"]
tags.appendIfAbsent("swift")  // no-op, returns false
tags.appendIfAbsent("macOS")  // appends, returns true
```
