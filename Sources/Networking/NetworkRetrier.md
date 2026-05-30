# NetworkRetrier

Configurable retry logic with exponential backoff, jitter, and preset policies for async operations.

## API

| Type | Description |
|---|---|
| `RetryPolicy` | Configures max attempts, delay strategy, retryable status codes, and error predicate |
| `RetryPolicy.aggressive` | 5 attempts, short exponential backoff (base 0.5s) |
| `RetryPolicy.conservative` | 3 attempts, longer exponential backoff (base 2.0s) |
| `RetryPolicy.once` | 2 attempts with a fixed 1-second delay |
| `RetryPolicy.none` | Single attempt, no retries |
| `DelayStrategy.fixed(delay:)` | Constant delay between retries |
| `DelayStrategy.exponential(base:multiplier:maxDelay:)` | Exponential backoff capped at `maxDelay` |
| `DelayStrategy.exponentialWithJitter(...)` | Exponential backoff plus random jitter |
| `DelayStrategy.custom(_:)` | Custom delay function from attempt index |
| `NetworkRetrier.execute(policy:operation:)` | Retry any async throwing closure |
| `NetworkRetrier.data(for:session:policy:)` | Retry a `URLRequest` with HTTP status checking |
| `NetworkRetrier.data(from:session:policy:)` | Retry a URL fetch with HTTP status checking |
| `RetryExhaustedError` | Thrown when all attempts are exhausted |
| `HTTPRetryableStatusError` | Wrapper for retryable HTTP status codes |

## Examples

### Basic retry with default policy

```swift
import SwiftUtilsNetworking

let url = URL(string: "https://api.example.com/data")!
let (data, response) = try await NetworkRetrier.data(from: url)
```

### Custom retry policy

```swift
let policy = RetryPolicy(
    maxAttempts: 5,
    strategy: .exponentialWithJitter(base: 0.5, multiplier: 2.0, maxDelay: 30.0, jitterRange: 0.5),
    retryableStatusCodes: [429, 500, 502, 503, 504],
    shouldRetry: { error in
        // Retry on timeout and connection loss only
        guard let urlError = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost].contains(urlError.code)
    }
)

let (data, response) = try await NetworkRetrier.data(from: url, policy: policy)
```

### Retry any async operation

```swift
let result = try await NetworkRetrier.execute(policy: .aggressive) {
    try await someFlakeyDatabaseQuery()
}
```

### Using presets

```swift
// Critical path — retry aggressively
let critical = try await NetworkRetrier.data(from: url, policy: .aggressive)

// Background sync — be patient
let background = try await NetworkRetrier.data(from: url, policy: .conservative)

// Quick check — one retry only
let quick = try await NetworkRetrier.data(from: url, policy: .once)
```

### Handling exhausted retries

```swift
do {
    let data = try await NetworkRetrier.data(from: url, policy: .conservative)
} catch let error as RetryExhaustedError {
    print("Failed after \(error.attempts) attempts: \(error.lastError)")
} catch {
    print("Non-retryable error: \(error)")
}
```
