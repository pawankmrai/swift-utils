# WebSocketClient

An async/await wrapper around `URLSessionWebSocketTask` that exposes the connection lifecycle and incoming messages as a single `AsyncStream`, with automatic reconnection (exponential backoff) and keep-alive pinging — no delegate boilerplate required.

## API

| Type | Description |
|---|---|
| `WebSocketClient` | The client. One instance per socket endpoint. |
| `WebSocketClient.Configuration` | Reconnect and ping tuning: `pingInterval`, `autoReconnect`, `maxReconnectAttempts`, `reconnectBaseDelay`, `reconnectMaxDelay` |
| `WebSocketClient.connect()` | Opens the socket, returns `AsyncStream<WebSocketEvent>` |
| `WebSocketClient.send(_:)` | Sends a `String` or `Data` frame |
| `WebSocketClient.send(_:encoder:)` | Encodes an `Encodable` value as JSON and sends it as text |
| `WebSocketClient.disconnect(closeCode:reason:)` | Closes the socket and disables auto-reconnect |
| `WebSocketClient.decode(_:as:decoder:)` | Static helper to JSON-decode a `WebSocketMessage` |
| `WebSocketMessage` | `.text(String)` or `.data(Data)` — `Sendable`, `Equatable` |
| `WebSocketEvent` | `.connected`, `.message`, `.disconnected`, `.reconnecting`, `.failure` |
| `WebSocketError` | `.notConnected`, `.encodingFailed` |

## Examples

### Basic connection and message loop

```swift
import SwiftUtilsNetworking

let client = WebSocketClient(url: URL(string: "wss://example.com/socket")!)
let events = client.connect()

Task {
    for await event in events {
        switch event {
        case .connected(let proto):
            print("connected, protocol:", proto ?? "none")
        case .message(.text(let text)):
            print("received:", text)
        case .message(.data(let data)):
            print("received \(data.count) bytes")
        case .disconnected(let code, _):
            print("closed:", code)
        case .reconnecting(let attempt):
            print("reconnecting, attempt", attempt)
        case .failure(let error):
            print("error:", error)
        }
    }
}

try await client.send("hello, server")
```

### Sending and receiving typed JSON payloads

```swift
struct ChatMessage: Codable {
    let room: String
    let text: String
}

try await client.send(ChatMessage(room: "general", text: "hi there"))

for await event in events {
    guard case .message(let message) = event else { continue }
    if let chat = try? WebSocketClient.decode(message, as: ChatMessage.self) {
        print("\(chat.room): \(chat.text)")
    }
}
```

### Custom reconnect and ping behavior

```swift
let config = WebSocketClient.Configuration(
    pingInterval: 15,
    autoReconnect: true,
    maxReconnectAttempts: 10,
    reconnectBaseDelay: 0.5,
    reconnectMaxDelay: 20
)

let client = WebSocketClient(
    url: URL(string: "wss://example.com/socket")!,
    headers: ["Authorization": "Bearer \(token)"],
    configuration: config
)
```

### Disabling auto-reconnect for a one-shot connection

```swift
let client = WebSocketClient(
    url: url,
    configuration: .init(autoReconnect: false)
)
let events = client.connect()

for await event in events {
    if case .disconnected = event { break } // stream finishes right after
}
```

### Clean shutdown

```swift
// Stops the keep-alive pings and reconnect loop, then closes the socket.
client.disconnect(closeCode: .normalClosure)
```
