# AsyncSemaphore

A counting semaphore for `async`/`await` code that **suspends tasks instead of blocking threads**.

`DispatchSemaphore.wait()` parks the calling thread. Inside Swift Concurrency that is risky — the cooperative thread pool is small, and a parked thread can starve or deadlock unrelated tasks. `AsyncSemaphore` suspends the awaiting task and frees the thread, resuming only when a permit is available. Use it to cap concurrency (downloads, decoding, DB writes), guard a limited resource pool, or serialize access to a non-reentrant API.

Waiters are served in **FIFO order**. The cancellable acquire path cooperates with structured concurrency: cancelling a waiting task throws `CancellationError` and removes it from the queue.

## API

| Type / Method | Description |
|---|---|
| `AsyncSemaphore(value: Int)` | Creates a semaphore with `value` permits (`value >= 0`) |
| `availablePermits: Int` | Snapshot of currently available permits (debugging/tests) |
| `wait() async` | Suspends until a permit is available; ignores cancellation |
| `waitUnlessCancelled() async throws` | Like `wait()`, but throws `CancellationError` if cancelled while waiting |
| `signal()` | Releases one permit; resumes the longest-waiting task if any |
| `withPermit(_:) async rethrows -> T` | Acquires a permit, runs the closure, and always releases — even on throw |

## Examples

### Cap concurrent work

```swift
// Never run more than 4 uploads at once.
let gate = AsyncSemaphore(value: 4)

await withTaskGroup(of: Void.self) { group in
    for file in files {
        group.addTask {
            await gate.withPermit {
                try? await uploader.upload(file)
            }
        }
    }
}
```

### Manual acquire / release

```swift
let gate = AsyncSemaphore(value: 1)

await gate.wait()
defer { gate.signal() }
try await criticalSection()
```

### Guard a fixed resource pool

```swift
// Only 2 database writers; extra callers wait their turn.
let writers = AsyncSemaphore(value: 2)

func persist(_ record: Record) async throws {
    try await writers.withPermit {
        try await database.write(record)
    }
}
```

### Cancellable wait

```swift
let gate = AsyncSemaphore(value: 0)

let task = Task {
    do {
        try await gate.waitUnlessCancelled()
        proceed()
    } catch is CancellationError {
        // The task was cancelled while queued — clean up and bail.
        rollback()
    }
}

// Later, if the screen is dismissed:
task.cancel()
```

### Throttle a flood of events

```swift
final class ThumbnailService {
    private let gate = AsyncSemaphore(value: 3)

    func thumbnail(for url: URL) async throws -> UIImage {
        try await gate.withPermit {
            try await Self.renderThumbnail(url)   // expensive
        }
    }
}
```

### Use as a one-shot signal

```swift
// value: 0 means the first waiter blocks until something signals.
let ready = AsyncSemaphore(value: 0)

Task {
    await warmUpCaches()
    ready.signal()          // unblock whoever is waiting
}

await ready.wait()          // proceed only after warm-up completes
startServingRequests()
```
