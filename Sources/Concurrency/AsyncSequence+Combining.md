# AsyncSequence+Combining

Free functions that combine multiple `AsyncSequence`s together — `merge`, `combineLatest`, and `zip` — the async/await counterparts to the equivalent Combine operators, with no external dependency.

Use these to interleave independent event streams, derive UI state from several inputs at once, or pair up two sequences element-by-element.

## API

| Type / Method | Description |
|---|---|
| `merge(_:_:...) -> AsyncThrowingStream<S.Element, Error>` | Interleaves elements from two or more homogeneous sequences as they arrive |
| `merge(_: [S]) -> AsyncThrowingStream<S.Element, Error>` | Array-based overload of `merge` for dynamically built collections of sequences |
| `combineLatest(_:_:) -> AsyncThrowingStream<(A.Element, B.Element), Error>` | Emits `(latestA, latestB)` whenever either source produces a value, once both have produced at least one |
| `zip(_:_:) -> AsyncThrowingStream<(A.Element, B.Element), Error>` | Pairs elements from two sequences in lockstep; finishes when the shorter sequence ends |

All three propagate errors: if any source sequence throws, the remaining sources are cancelled and the error is re-thrown from the combined stream. Cancelling iteration of the returned stream (e.g. breaking out of a `for try await` loop, or cancelling the enclosing `Task`) cancels every source sequence.

## Examples

### Merge independent event sources

```swift
let events = merge(sensorAStream, sensorBStream, sensorCStream)
for try await reading in events {
    print("New reading:", reading)
}
```

### Merge a dynamically built list of sequences

```swift
let feeds: [AsyncStream<Notification>] = channels.map { $0.notificationStream }
for try await notification in merge(feeds) {
    inbox.append(notification)
}
```

### Drive search results off a query and a filter stream

```swift
let stream = combineLatest(searchBar.textStream, filterMenu.selectionStream)
for try await (query, filter) in stream {
    await search(query, filter: filter)
}
```

### Pair two sequences element-by-element

```swift
let paired = zip(namesStream, scoresStream)
for try await (name, score) in paired {
    print("\(name): \(score)")
}
```

### Stop processing when the user navigates away

```swift
let task = Task {
    for try await (query, filter) in combineLatest(queryStream, filterStream) {
        await performSearch(query, filter: filter)
    }
}

// Later, e.g. in `onDisappear`:
task.cancel() // cancels both `queryStream` and `filterStream` iteration
```

### Handling upstream failures

```swift
do {
    for try await value in merge(primaryFeed, backupFeed) {
        handle(value)
    }
} catch {
    // Either feed throwing cancels the other and surfaces the error here.
    logger.error("Feed failed: \(error)")
}
```
