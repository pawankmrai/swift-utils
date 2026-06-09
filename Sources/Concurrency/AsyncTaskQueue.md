# AsyncTaskQueue

An actor-based task queue that controls the maximum number of async operations running simultaneously — serial, rate-limited, or fully concurrent.

Use it to serialise file writes, limit parallel network calls, or drain pending work on sign-out.

## API

| Type / Method | Description |
|---|---|
| `AsyncTaskQueue(maxConcurrency:)` | Create a queue; `maxConcurrency: 1` → serial |
| `AsyncTaskQueue.serial` | Convenience: serial queue (maxConcurrency 1) |
| `AsyncTaskQueue.concurrentFour` | Convenience: queue capped at 4 concurrent tasks |
| `enqueue(priority:operation:) async throws -> T` | Enqueue a throwing operation; await its result |
| `enqueue(priority:operation:) async -> T` | Enqueue a non-throwing operation; await its result |
| `submit(priority:operation:) -> Task<Void, Error>` | Fire-and-forget; returns a cancellable `Task` |
| `cancelPending()` | Resume all waiting continuations so they can exit |
| `activeCount: Int` | Number of operations currently executing |
| `pendingCount: Int` | Number of operations waiting for a slot |
| `Priority` | `.high`, `.medium`, `.low` — maps to `TaskPriority` |

## Examples

### Serial queue — one upload at a time

```swift
let uploadQueue = AsyncTaskQueue.serial

func uploadPhoto(_ data: Data) async throws -> URL {
    try await uploadQueue.enqueue {
        try await s3Client.upload(data)
    }
}

// Callers from any Task/actor compete for the single slot.
async let url1 = uploadPhoto(photo1)
async let url2 = uploadPhoto(photo2)
let (a, b) = try await (url1, url2)   // sequential despite async let
```

### Rate-limited network calls

```swift
// Never fire more than 3 requests simultaneously.
let networkQueue = AsyncTaskQueue(maxConcurrency: 3)

let results = try await withThrowingTaskGroup(of: Post.self) { group in
    for id in postIDs {
        group.addTask {
            try await networkQueue.enqueue {
                try await api.fetchPost(id: id)
            }
        }
    }
    return try await group.reduce(into: []) { $0.append($1) }
}
```

### Await result inline

```swift
let queue = AsyncTaskQueue(maxConcurrency: 2)

let user: User = try await queue.enqueue {
    try await userService.fetchCurrentUser()
}
print(user.name)
```

### Fire-and-forget with cancellation

```swift
let syncQueue = AsyncTaskQueue.serial
var syncTask: Task<Void, Error>?

func startSync() {
    syncTask = syncQueue.submit {
        try await cloudService.sync()
    }
}

func stopSync() {
    syncTask?.cancel()
    syncTask = nil
}
```

### Cancel pending work on sign-out

```swift
class SessionManager {
    let operationQueue = AsyncTaskQueue(maxConcurrency: 4)

    func signOut() async {
        // Stop queued work from starting.
        await operationQueue.cancelPending()
        // Then sign out...
    }
}
```

### Inspect queue depth

```swift
let queue = AsyncTaskQueue(maxConcurrency: 2)

print("Active: \(await queue.activeCount)")   // 0
print("Pending: \(await queue.pendingCount)") // 0

// After submitting work:
print("Active: \(await queue.activeCount)")   // up to 2
print("Pending: \(await queue.pendingCount)") // remainder
```

### Priority hints

```swift
let queue = AsyncTaskQueue(maxConcurrency: 3)

// High-priority thumbnail generation
await queue.enqueue(priority: .high) {
    await thumbnailCache.generate(for: asset)
}

// Low-priority prefetch in the background
queue.submit(priority: .low) {
    await prefetchImages(urls: nextPageURLs)
}
```
