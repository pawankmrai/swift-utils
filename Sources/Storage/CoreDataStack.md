# CoreDataStack

A generic, dependency-free wrapper around `NSPersistentContainer` that adds typed fetch/save/delete helpers, an async/await bridge for background work, and an in-memory mode for SwiftUI previews and unit tests. It accepts any `NSManagedObjectModel` — including one built entirely in code — so it works in Swift packages and test targets with no `.xcdatamodeld` file.

## API

| Type / Method | Description |
|---|---|
| `CoreDataStack.StoreType` | `.sqlite` (durable, on-disk) or `.inMemory` (ephemeral, for previews/tests) |
| `CoreDataStackError` | Typed errors: `modelNotFound`, `loadFailed`, `saveFailed`, `fetchFailed`, `batchDeleteFailed` |
| `init(modelName:model:storeType:storeURL:bundle:)` | Loads or creates a persistent container; throws if the store fails to load |
| `container` | The underlying `NSPersistentContainer` |
| `storeType` | The backend the stack was configured with |
| `viewContext` | Main-thread context for UI binding |
| `newBackgroundContext()` | Background context with auto-merge into `viewContext` |
| `performBackgroundTask(_:)` | Runs a closure on a background context with async/await, returning its result |
| `save(_:)` | Saves a context only if it has uncommitted changes |
| `create(_:in:)` | Inserts and returns a new, unsaved instance of a managed object type |
| `fetch(_:predicate:sortDescriptors:limit:in:)` | Typed fetch with optional predicate, sort, and limit |
| `count(_:predicate:in:)` | Counts matching entities without loading them into memory |
| `delete(_:in:)` | Deletes a single object and saves |
| `batchDelete(_:predicate:in:)` | Deletes all matching objects; uses `NSBatchDeleteRequest` on `.sqlite`, fetch-then-delete on `.inMemory` |

## Examples

### Set up a stack from your app's `.xcdatamodeld`

```swift
import SwiftUtilsStorage

let stack = try CoreDataStack(modelName: "MyAppModel")
```

### In-memory stack for SwiftUI previews or tests

```swift
let model = NSManagedObjectModel.mergedModel(from: [.main])!
let previewStack = try CoreDataStack(modelName: "MyAppModel", model: model, storeType: .inMemory)
```

### Create, save, and fetch

```swift
let context = stack.viewContext

let note = stack.create(Note.self, in: context)
note.id = UUID()
note.title = "Pick up groceries"
note.createdAt = Date()

try stack.save(context)

let allNotes = try stack.fetch(Note.self, in: context)
print(allNotes.count) // 1
```

### Fetch with a predicate, sort, and limit

```swift
let recentUnread = try stack.fetch(
    Note.self,
    predicate: NSPredicate(format: "isRead == NO"),
    sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
    limit: 20,
    in: stack.viewContext
)
```

### Count without loading objects

```swift
let unreadCount = try stack.count(
    Note.self,
    predicate: NSPredicate(format: "isRead == NO"),
    in: stack.viewContext
)
```

### Do heavy work off the main thread

```swift
let importedCount = try await stack.performBackgroundTask { context in
    for payload in downloadedPayloads {
        let note = stack.create(Note.self, in: context)
        note.id = payload.id
        note.title = payload.title
        note.createdAt = payload.createdAt
    }
    try context.save()
    return downloadedPayloads.count
}
print("Imported \(importedCount) notes")
```

### Delete a single object

```swift
if let note = try stack.fetch(Note.self, in: stack.viewContext).first {
    try stack.delete(note, in: stack.viewContext)
}
```

### Batch-delete with a predicate

```swift
// Purge notes older than 30 days. Uses NSBatchDeleteRequest on disk-backed stores.
let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
let removed = try stack.batchDelete(
    Note.self,
    predicate: NSPredicate(format: "createdAt < %@", cutoff as NSDate),
    in: stack.viewContext
)
print("Removed \(removed) stale notes")
```

### Handle store load failures

```swift
do {
    let stack = try CoreDataStack(modelName: "MyAppModel")
} catch CoreDataStackError.loadFailed(let underlying) {
    print("Could not open the store: \(underlying.localizedDescription)")
} catch CoreDataStackError.modelNotFound(let name) {
    print("No model named \(name) was found in the bundle")
}
```
