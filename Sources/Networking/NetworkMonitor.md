# NetworkMonitor

A lightweight async/await-first network connectivity monitor backed by `NWPathMonitor`. Observe connectivity changes via `AsyncStream`, Combine, or synchronous property access — all in a thread-safe, lifecycle-aware wrapper.

## API

| Type / Member | Description |
|---|---|
| `NetworkMonitor` | Main class. Wraps `NWPathMonitor`. Thread-safe. |
| `NetworkMonitor.init()` | Monitors all available interfaces. |
| `NetworkMonitor.init(requiring:)` | Monitors a single interface type (`.wifi`, `.cellular`, etc.). |
| `NetworkMonitor.start()` | Begins monitoring. Safe to call multiple times. |
| `NetworkMonitor.stop()` | Stops monitoring and finishes all active `AsyncStream` subscriptions. |
| `NetworkMonitor.status` | The most recently observed `NetworkStatus`. Initially `.unknown`. |
| `NetworkMonitor.isConnected` | `true` when `status` is `.connected(_)`. |
| `NetworkMonitor.statusStream` | `AsyncStream<NetworkStatus>` — emits on every change. Immediately yields current status if known. |
| `NetworkMonitor.statusPublisher` | `AnyPublisher<NetworkStatus, Never>` for Combine subscribers. |
| `NetworkMonitor.waitForConnection(timeout:)` | Awaits a `.connected` status or returns `nil` after the given timeout (default 10 s). |
| `NetworkStatus` | Enum: `.connected(NetworkInterface)`, `.disconnected`, `.unknown`. |
| `NetworkStatus.isConnected` | `true` when status is `.connected(_)`. |
| `NetworkInterface` | Enum: `.wifi`, `.cellular`, `.wiredEthernet`, `.loopback`, `.other`. |

## Examples

### Start monitoring and react to changes

```swift
import SwiftUtilsNetworking

let monitor = NetworkMonitor()
monitor.start()

Task {
    for await status in monitor.statusStream {
        switch status {
        case .connected(let interface):
            print("Online via \(interface)") // e.g. "Online via WiFi"
        case .disconnected:
            print("No network connection")
        case .unknown:
            break
        }
    }
}
```

### Synchronous status check

```swift
let monitor = NetworkMonitor()
monitor.start()

// Check after a brief delay to allow NWPathMonitor to deliver the first path
if monitor.isConnected {
    print("Current interface: \(monitor.status)")
}
```

### Wait for connectivity before making a request

```swift
let monitor = NetworkMonitor()
monitor.start()

guard let status = await monitor.waitForConnection(timeout: 5) else {
    throw AppError.noNetwork
}
print("Connected, proceeding with request via \(status)")
let (data, _) = try await URLSession.shared.data(from: apiURL)
```

### Monitor a single interface (WiFi only)

```swift
let wifiMonitor = NetworkMonitor(requiring: .wifi)
wifiMonitor.start()

for await status in wifiMonitor.statusStream {
    print("WiFi status: \(status)")
    // .connected(.wifi) when WiFi is available; .disconnected when not
}
```

### Combine integration (SwiftUI / UIKit)

```swift
import Combine

class ViewModel: ObservableObject {
    @Published var isOnline = false
    private let monitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()

    init() {
        monitor.statusPublisher
            .map(\.isConnected)
            .receive(on: DispatchQueue.main)
            .assign(to: &$isOnline)
        monitor.start()
    }

    deinit { monitor.stop() }
}
```

### SwiftUI view with live connectivity badge

```swift
struct ContentView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        VStack {
            Circle()
                .fill(vm.isOnline ? .green : .red)
                .frame(width: 12, height: 12)
            Text(vm.isOnline ? "Online" : "Offline")
        }
    }
}
```

### Retry request until network is available

```swift
func fetchWithRetry(url: URL, monitor: NetworkMonitor) async throws -> Data {
    for _ in 0..<3 {
        guard monitor.isConnected else {
            await monitor.waitForConnection(timeout: 30)
            continue
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
    throw URLError(.notConnectedToInternet)
}
```
