# CodableStore

A lightweight, thread-safe, disk-backed collection store for a single `Codable & Identifiable` model type — a tiny local database for small datasets like drafts, bookmarks, settings lists, or cached records. Every mutation is persisted to a single JSON file with an atomic write; reads are served from a fast in-memory snapshot.

## API

| Type / Method | Description |
|---|---|
| `CodableStore<Element>` | Generic store where `Element: Codable & Identifiable` and `Element.ID: Hashable` |
| `CodableStoreError` | Typed errors: `notFound`, `encodingFailed`, `decodingFailed`, `underlyingError` |
| `init(filename:directory:encoder:decoder:)` | Open (and load) a store backed by a JSON file; `directory` defaults to Application Support |
| `all() -> [Element]` | Every element, in insertion order |
| `count: Int` | Number of stored elements |
| `element(withID:) -> Element?` | O(1) lookup by id |
| `contains(id:) -> Bool` | Whether an element with the id exists |
| `filter(_:) -> [Element]` | Elements matching a predicate, in insertion order |
| `upsert(_:)` | Insert a new element or update the existing one with the same id |
| `upsert(_:)` (array) | Insert/update many elements in one atomic write |
| `delete(id:)` | Remove an element by id; throws `notFound` if absent |
| `deleteAll(where:) -> Int` | Remove all elements matching a predicate; returns the count removed |
| `removeAll()` | Remove every element and persist the empty collection |
| `defaultEncoder` / `defaultDecoder` | ISO 8601 date strategy; encoder pretty-prints with sorted keys |

## Examples

### Persist a list of notes

```swift
import SwiftUtilsStorage

struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
}

let store = try CodableStore<Note>(filename: "notes.json")

// Insert
try store.upsert(Note(id: UUID(), text: "Buy milk", createdAt: Date()))

// Read everything back (in insertion order)
for note in store.all() {
    print(note.text)
}
```

### Update an existing element in place

```swift
guard var note = store.all().first else { return }
note.text = "Buy oat milk"
try store.upsert(note) // same id → updates, keeps its position
```

### Look up, check, and delete by id

```swift
if store.contains(id: noteID) {
    let note = store.element(withID: noteID)
    print(note?.text ?? "—")
    try store.delete(id: noteID)
}
```

### Query with a predicate

```swift
struct Task: Codable, Identifiable {
    let id: Int
    var title: String
    var isDone: Bool
}

let tasks = try CodableStore<Task>(filename: "tasks.json")

let pending = tasks.filter { !$0.isDone }
let completedCount = try tasks.deleteAll { $0.isDone } // clear finished tasks
print("Archived \(completedCount) completed tasks")
```

### Batch import in a single write

```swift
let imported: [Note] = try decodeBundledSeedData()
try store.upsert(imported) // one atomic disk write for the whole batch
```

### Data survives app launches

```swift
// First launch
let store = try CodableStore<Note>(filename: "notes.json")
try store.upsert(Note(id: UUID(), text: "Persisted", createdAt: Date()))

// Next launch — same filename reloads what was saved
let reopened = try CodableStore<Note>(filename: "notes.json")
print(reopened.count) // 1
```

### Use a custom directory (e.g. a shared App Group container)

```swift
let container = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.myapp")!

let shared = try CodableStore<Note>(filename: "notes.json", directory: container)
```

### Handle a missing element gracefully

```swift
do {
    try store.delete(id: someID)
} catch CodableStoreError.notFound(let id) {
    print("Nothing to delete for id \(id)")
}
```

> **Note:** `CodableStore` is designed for modest collections (hundreds to low thousands of items). For large datasets or relational queries, prefer `CoreDataStack`.
