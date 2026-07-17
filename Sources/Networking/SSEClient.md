# SSEClient

An async/await client for Server-Sent Events (`text/event-stream`) built on `URLSession`'s byte-streaming API. Parses the SSE wire format (`id`/`event`/`data`/`retry` fields, multi-line data, comments) into typed messages delivered through a single `AsyncStream`, with `Last-Event-ID` resumption and exponential-backoff auto-reconnect — no third-party dependency required.

## API

| Type | Description |
|---|---|
| `SSEClient` | The client. One instance per stream endpoint. |
| `SSEClient.Configuration` | Reconnect tuning: `autoReconnect`, `maxReconnectAttempts`, `reconnectBaseDelay`, `reconnectMaxDelay` |
| `SSEClient.connect()` | Opens the request, returns `AsyncStream<SSEEvent>` |
| `SSEClient.disconnect()` | Closes the stream and disables auto-reconnect |
| `SSEClient.decode(_:as:decoder:)` | Static helper to JSON-decode an `SSEMessage`'s `data` payload |
| `SSEMessage` | `id`, `event`, `data`, `retry` — `Sendable`, `Equatable` |
| `SSEEvent` | `.open`, `.message`, `.reconnecting`, `.failure`, `.closed` |
| `SSEClientError` | `.invalidResponse`, `.httpError(statusCode:)` |

## Examples

### Basic connection and message loop

```swift
import SwiftUtilsNetworking

let client = SSEClient(url: URL(string: "https://example.com/stream")!)
let events = client.connect()

Task {
    for await event in events {
        switch event {
        case .open:
            print("connected")
        case .message(let message):
            print("[\(message.event)]", message.data)
        case .reconnecting(let attempt):
            print("reconnecting, attempt", attempt)
        case .failure(let error):
            print("error:", error)
        case .closed:
            print("stream closed")
        }
    }
}
```

### Receiving typed JSON payloads

```swift
struct PriceUpdate: Codable {
    let symbol: String
    let price: Decimal
}

for await event in events {
    guard case .message(let message) = event, message.event == "price" else { continue }
    if let update = try? SSEClient.decode(message, as: PriceUpdate.self) {
        print("\(update.symbol): \(update.price)")
    }
}
```

### Authenticated stream with custom reconnect policy

```swift
let client = SSEClient(
    url: URL(string: "https://example.com/notifications")!,
    headers: ["Authorization": "Bearer \(token)"],
    configuration: .init(
        autoReconnect: true,
        maxReconnectAttempts: 20,
        reconnectBaseDelay: 0.5,
        reconnectMaxDelay: 15
    )
)
let events = client.connect()
```

### Resuming after a dropped connection

`SSEClient` automatically tracks the last `id:` it saw and resends it as the
`Last-Event-ID` header on reconnect, so a well-behaved server can replay only
the events the client missed — no extra code required:

```swift
// Server sends:
//   id: 42
//   event: message
//   data: hello
//
// (blank line ends the event)
//
// If the connection drops after this, the next reconnect request
// automatically includes: Last-Event-ID: 42
```

### Handling a server-specified reconnect delay

If the server sends a `retry:` field (milliseconds), `SSEClient` uses it in
place of the exponential-backoff delay for the next reconnect attempt only:

```swift
// Server sends: retry: 5000
// -> next reconnect waits 5s instead of the computed backoff delay
```

### One-shot, non-reconnecting stream

```swift
let client = SSEClient(
    url: url,
    configuration: .init(autoReconnect: false)
)
let events = client.connect()

for await event in events {
    if case .closed = event { break } // stream finishes when the server closes it
}
```

### Clean shutdown

```swift
// Cancels the underlying task and disables further reconnect attempts.
client.disconnect()
```
