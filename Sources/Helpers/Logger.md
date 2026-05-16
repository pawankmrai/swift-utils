# SwiftLogger

A configurable, thread-safe logger with severity levels, category tagging, and pluggable destinations.

## API

| Method / Property | Description |
|---|---|
| `verbose(_:)`, `debug(_:)`, `info(_:)` | Log at level |
| `warning(_:)`, `error(_:)`, `fatal(_:)` | Log at level |
| `minimumLevel` | Filter out messages below this level |
| `addDestination(_:)` | Add a custom log destination |
| `ConsoleDestination` | Built-in destination using os.Logger / print |

## Examples

```swift
import SwiftUtilsHelpers

// Basic usage
let log = SwiftLogger(subsystem: "com.myapp", category: "Networking")

log.info("Request started for /users")
log.debug("Headers: \(request.allHTTPHeaderFields ?? [:])")
log.warning("Rate limit approaching: \(remaining) left")
log.error("Failed to decode response: \(error)")

// Filter by minimum level — silences verbose/debug/info
log.minimumLevel = .warning

// Messages below minimum are never evaluated (uses @autoclosure)
log.debug("This expensive computation: \(expensiveCall())")  // skipped entirely

// Multiple categories
let networkLog = SwiftLogger(subsystem: "com.myapp", category: "Network")
let uiLog = SwiftLogger(subsystem: "com.myapp", category: "UI")

// Custom destination
class FileDestination: LogDestination {
    func log(level: LogLevel, message: String, category: String) {
        // Write to file...
    }
}
log.addDestination(FileDestination())
```
