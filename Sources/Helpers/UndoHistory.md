# UndoHistory

A thread-safe, snapshot-based undo/redo history for any value type, with named actions, time-window coalescing, a bounded depth, and saved-state ("dirty") tracking.

`UndoManager` asks you to register an inverse operation for every change, which gets awkward with value types and SwiftUI state. `UndoHistory` takes the simpler route: it records successive values of your model. Undo restores the previous snapshot, redo re-applies the next one. Structs, arrays, and enums are cheap to copy (copy-on-write), so this fits most editor, form, and drawing use cases.

## API

| Type / Method | Description |
|---|---|
| `UndoHistory<Value>(_:limit:isEqual:now:)` | Creates a history at an initial value. `limit` caps undo depth (default 100); an optional `isEqual` turns duplicate records into no-ops; `now` is an injectable clock |
| `UndoHistory(_:limit:now:)` *(Value: Equatable)* | Convenience init that skips records equal to the current value automatically |
| `current: Value` | The current value |
| `record(_:actionName:coalescingKey:coalescingWindow:)` | Records a new value. Records that share a `coalescingKey` within `coalescingWindow` seconds (default 1s) merge into one undo step. Clears redo |
| `update(actionName:coalescingKey:coalescingWindow:_:)` | Mutates a copy of `current` in place and records it |
| `undo() -> Value?` | Restores the previous value; `nil` if there's nothing to undo |
| `redo() -> Value?` | Re-applies the last undone value; `nil` if there's nothing to redo |
| `canUndo` / `canRedo` | Whether a step is available |
| `undoCount` / `redoCount` | Number of available steps |
| `undoActionName` / `redoActionName` | Action names for menu titles such as "Undo Typing" |
| `hasUnsavedChanges: Bool` | `true` when `current` differs from the last saved snapshot. Undoing back to it counts as clean |
| `markSaved()` | Marks the current snapshot as saved |
| `clear()` | Drops all undo/redo steps but keeps `current` |
| `onChange(_:)` | Handler called after every change to `current` (record, undo, redo) |
| `limit: Int` | Maximum undo depth; the oldest steps are discarded first |

## Examples

### Basic undo/redo

```swift
import SwiftUtilsHelpers

let history = UndoHistory(0)
history.record(1, actionName: "Increment")
history.record(2, actionName: "Increment")

history.undoActionName  // "Increment"
history.undo()          // 1
history.undo()          // 0
history.redo()          // 1
history.record(10)      // redo stack is cleared
history.canRedo         // false
```

### Text editor with keystroke coalescing

Without coalescing, each keystroke would be its own undo step. With a shared key, a burst of typing becomes one step, and a pause longer than the window starts a new one:

```swift
struct Note: Equatable {
    var title = ""
    var body = ""
}

let history = UndoHistory(Note(), limit: 200)

func textDidChange(_ newBody: String) {
    history.update(actionName: "Typing", coalescingKey: "body", coalescingWindow: 1.5) {
        $0.body = newBody
    }
}

func titleDidChange(_ newTitle: String) {
    // A different key, so switching fields always starts a new undo step.
    history.update(actionName: "Rename", coalescingKey: "title") { $0.title = newTitle }
}
```

### SwiftUI view model with undo buttons

```swift
@MainActor
final class DrawingViewModel: ObservableObject {
    struct Drawing: Equatable { var strokes: [Stroke] = [] }

    @Published private(set) var drawing = Drawing()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private let history = UndoHistory(Drawing(), limit: 50)

    init() {
        history.onChange { [weak self] value in
            Task { @MainActor in self?.sync(value) }
        }
    }

    func add(_ stroke: Stroke) {
        history.update(actionName: "Draw") { $0.strokes.append(stroke) }
    }

    func clearCanvas() {
        history.record(Drawing(), actionName: "Clear")
    }

    func undo() { history.undo() }
    func redo() { history.redo() }

    private func sync(_ value: Drawing) {
        drawing = value
        canUndo = history.canUndo
        canRedo = history.canRedo
    }
}

struct DrawingToolbar: View {
    @ObservedObject var model: DrawingViewModel

    var body: some View {
        HStack {
            Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
            Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
        }
    }
}
```

### Unsaved-changes prompt

```swift
let history = UndoHistory(loadedDocument)

func save() async throws {
    try await api.save(history.current)
    history.markSaved()
}

func closeTapped() {
    if history.hasUnsavedChanges {
        presentDiscardChangesAlert()
    } else {
        dismiss()
    }
}

// Edit, then undo back to the saved state: hasUnsavedChanges is false again.
```

### Dynamic menu titles (UIKit)

```swift
override func validate(_ command: UICommand) {
    switch command.action {
    case #selector(undoTapped):
        command.title = history.undoActionName.map { "Undo \($0)" } ?? "Undo"
        command.attributes = history.canUndo ? [] : .disabled
    case #selector(redoTapped):
        command.title = history.redoActionName.map { "Redo \($0)" } ?? "Redo"
        command.attributes = history.canRedo ? [] : .disabled
    default:
        super.validate(command)
    }
}
```

### Non-Equatable values and custom equality

```swift
struct Layer { var id: UUID; var image: CGImage; var revision: Int }

// Compare by revision instead of pixel data.
let layers = UndoHistory([Layer](), isEqual: { a, b in
    a.map(\.revision) == b.map(\.revision)
})
```

### Deterministic tests with an injected clock

```swift
var time = Date(timeIntervalSince1970: 0)
let history = UndoHistory("", now: { time })

history.record("a", coalescingKey: "typing")
time += 0.5
history.record("ab", coalescingKey: "typing")   // merged
time += 5
history.record("abc", coalescingKey: "typing")  // new step

XCTAssertEqual(history.undoCount, 2)
```

## Notes

- Snapshots are stored by value, so keep `Value` reasonably small or copy-on-write (standard collections are). For very large models, record a lightweight state struct instead of the whole thing.
- Coalescing only merges into the most recent step, and only while the redo stack is empty. Undo/redo always breaks a coalescing run.
- `onChange` handlers run synchronously on the calling thread, after the internal lock is released, so they can read `canUndo` and similar properties safely. Hop to the main actor for UI work.
- When `limit` is exceeded, the oldest snapshots are dropped. If the saved snapshot is dropped, `hasUnsavedChanges` stays `true` until you call `markSaved()` again.
