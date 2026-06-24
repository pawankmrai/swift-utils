# AsyncTimeout

Free functions that race an async, throwing operation against a timer — so any `await` call can be given a time budget without hand-rolling `withThrowingTaskGroup` every time.

Use it to bound flaky network calls, prevent a slow dependency from hanging a UI flow, or fall back to cached data when a fetch takes too long.

## API

| Type / Method | Description |
|---|---|
| `TimeoutError` | `Error` thrown when the time budget elapses; carries `seconds` and a `errorDescription` |
| `withTimeout(seconds:operation:) async throws -> T` | Runs `operation`; throws `TimeoutError` if it doesn't finish in time |
| `withTimeout(seconds:default:operation:) async -> T` | Runs `operation`; returns `defaultValue` instead of throwing on timeout *or* failure |
| `withTimeoutOrNil(seconds:operation:) async throws -> T?` | Runs `operation`; returns `nil` on timeout, rethrows any other error |

## Examples

### Bound a network call

```swift
let user = try await withTimeout(seconds: 5) {
    try await api.fetchUser(id: 42)
}
```

### Distinguish timeout from failure

```swift
do {
    let post = try await withTimeout(seconds: 3) {
        try await api.fetchPost(id: postID)
    }
    show(post)
} catch let error as TimeoutError {
    showSlowConnectionBanner()
} catch {
    showErrorAlert(error)
}
```

### Fall back to a default value

```swift
// Never blocks the UI for more than 2 seconds; falls back silently
// on timeout *or* on any thrown error.
let config = await withTimeout(seconds: 2, default: RemoteConfig.fallback) {
    try await configService.fetchLatest()
}
```

### Treat timeout as "no result" rather than an error

```swift
// Errors other than timing out (e.g. decoding failures) still propagate.
if let suggestions = try await withTimeoutOrNil(seconds: 1.5, operation: search.fetchSuggestions) {
    display(suggestions)
} else {
    // Timed out — show cached/previous suggestions instead.
    display(cachedSuggestions)
}
```

### Combine with `TaskGroup` for parallel bounded calls

```swift
let results = try await withThrowingTaskGroup(of: Post.self) { group in
    for id in postIDs {
        group.addTask {
            try await withTimeout(seconds: 4) {
                try await api.fetchPost(id: id)
            }
        }
    }
    return try await group.reduce(into: []) { $0.append($1) }
}
```

### Respecting cancellation inside the operation

```swift
// withTimeout cancels the operation's Task when the timer wins, but the
// operation itself must check for cancellation to actually stop early.
let report = try await withTimeout(seconds: 10) {
    var partial = Report()
    for chunk in chunks {
        try Task.checkCancellation()
        partial.append(try await process(chunk))
    }
    return partial
}
```
