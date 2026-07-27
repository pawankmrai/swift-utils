# AsyncBatcher

Collects individual async requests submitted from anywhere in the app and executes them together as a single batch — either once `maxBatchSize` items have accumulated, or after `maxDelay` has elapsed since the first item of the batch arrived, whichever comes first.

This is the inverse of a deduplicating coordinator like `SingleFlight`: instead of collapsing *identical* calls into one, `AsyncBatcher` coalesces *distinct* calls that are cheaper to perform together than one at a time. Typical uses: marking a dozen notifications read in one API call instead of a dozen, batching analytics events before sending them, coalescing Core Data saves, or grouping GraphQL field resolvers into one query.

The batch `handler` must return exactly one result per item, **in the same order** the items were given. If it can't produce a result for a particular item, it should throw instead — every caller in that batch then receives the thrown error.

## API

| Type / Method | Description |
|---|---|
| `AsyncBatcher<Item, Output>(maxBatchSize:maxDelay:handler:)` | Creates a batcher. `maxBatchSize` defaults to `.max` (size never triggers a flush on its own); `maxDelay` (seconds) is required |
| `add(_:) async throws -> Output` | Queues an item for the next batch and suspends until that batch has executed, returning this item's result |
| `pendingCount: Int` | Number of items currently queued, awaiting the next flush |
| `flushNow() async` | Immediately executes the current batch, without waiting for `maxDelay` or `maxBatchSize` |
| `cancelAll()` | Rejects every pending request with `AsyncBatcherError.cancelled` and discards them without calling the handler |
| `AsyncBatcherError.cancelled` | The batcher was torn down while this item's request was still pending |
| `AsyncBatcherError.resultCountMismatch(expected:actual:)` | The handler returned a different number of results than items given |

## Examples

### Batch profile lookups triggered by scrolling cells

```swift
let profileBatcher = AsyncBatcher<String, UserProfile>(maxBatchSize: 20, maxDelay: 0.05) { ids in
    try await api.fetchProfiles(ids: ids) // one network call for the whole batch
}

// Called from `willDisplay cell` as the user scrolls. Every call landing
// within the same 50ms window (or the first 20 of them) becomes one
// request instead of one round trip per cell.
final class ProfileCell: UITableViewCell {
    func configure(userID: String) async {
        do {
            let profile = try await profileBatcher.add(userID)
            apply(profile)
        } catch {
            showFallbackAvatar()
        }
    }
}
```

### Coalesce "mark as read" calls

```swift
let readReceiptBatcher = AsyncBatcher<String, Void>(maxBatchSize: 50, maxDelay: 0.2) { notificationIDs in
    try await api.markNotificationsRead(ids: notificationIDs)
    return Array(repeating: (), count: notificationIDs.count)
}

func notificationDidBecomeVisible(_ id: String) {
    Task {
        try? await readReceiptBatcher.add(id)
    }
}
```

### Batch analytics events before sending

```swift
struct AnalyticsEvent: Sendable {
    let name: String
    let properties: [String: String]
}

let eventBatcher = AsyncBatcher<AnalyticsEvent, Void>(maxBatchSize: 25, maxDelay: 1.0) { events in
    try await analyticsAPI.sendBatch(events)
    return Array(repeating: (), count: events.count)
}

func track(_ event: AnalyticsEvent) {
    Task { try? await eventBatcher.add(event) }
}
```

### Force a flush before the screen disappears

```swift
final class FeedViewController: UIViewController {
    private let batcher = AsyncBatcher<String, ArticleSummary>(maxBatchSize: 15, maxDelay: 0.1) { ids in
        try await api.fetchSummaries(ids: ids)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Don't leave requests waiting on a timer the user will never see resolve.
        Task { await batcher.flushNow() }
    }
}
```

### Handle a result-count mismatch or handler failure

```swift
do {
    let summary = try await batcher.add(articleID)
    display(summary)
} catch AsyncBatcherError.resultCountMismatch(let expected, let actual) {
    logger.error("Batch handler returned \(actual) results for \(expected) items")
} catch AsyncBatcherError.cancelled {
    // The batcher was torn down (e.g. on sign-out) before this item ran.
} catch {
    showError(error)
}
```

### Cancel outstanding requests on sign-out

```swift
final class SessionController {
    private let batcher = AsyncBatcher<String, UserProfile>(maxDelay: 0.05) { ids in
        try await api.fetchProfiles(ids: ids)
    }

    func signOut() async {
        // Every caller currently queued receives AsyncBatcherError.cancelled
        // instead of a result computed after the session ended.
        await batcher.cancelAll()
        clearLocalState()
    }
}
```

### Inspect queue depth

```swift
let pending = await batcher.pendingCount
statusLabel.text = "\(pending) request(s) waiting to batch"
```
