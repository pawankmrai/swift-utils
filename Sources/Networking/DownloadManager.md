# DownloadManager

An actor-based file downloader with request de-duplication, a bounded number of concurrent transfers, and observable progress via `AsyncThrowingStream`.

Calling for the same URL while a download is already running attaches to that in-flight transfer instead of starting a second one, so every caller sees the same progress and receives the same file. Once a URL has finished downloading, later calls return the cached file immediately (as long as it's still on disk) without touching the network again.

## API

| Type / Member | Description |
|---|---|
| `DownloadManager` | Actor. Downloads files over HTTP(S) with de-duplication, concurrency limiting, and progress. |
| `DownloadManager.shared` | A shared, app-wide instance backed by `URLSession.shared`. |
| `DownloadManager.init(destinationDirectory:maxConcurrentDownloads:session:)` | Creates a manager with a custom save directory (defaults to `Caches/Downloads`), transfer concurrency limit (default `4`), and `URLSession`. |
| `DownloadManager.events(for:filename:)` | `AsyncThrowingStream<DownloadEvent, Error>`. Starts or attaches to a download for a URL, streaming `.progress` updates and a terminal `.completed`. |
| `DownloadManager.download(_:filename:)` | `async throws -> URL`. Awaits the full download and returns just the local file URL. |
| `DownloadManager.cancel(_:)` | Cancels the in-flight download for a URL, if any. |
| `DownloadManager.cancelAll()` | Cancels every in-flight download. |
| `DownloadManager.isDownloading(_:)` | Returns whether a URL currently has an active transfer. |
| `DownloadManager.forget(_:)` | Deletes a previously downloaded file and clears its cached state, forcing a re-download next time. |
| `DownloadEvent.progress(bytesWritten:totalBytes:)` | Bytes written so far; `totalBytes` is `nil` when the server omits `Content-Length`. |
| `DownloadEvent.completed(fileURL:)` | The terminal event — the file is saved and ready to use. |
| `DownloadEvent.fractionCompleted` | `Double?` — a `0...1` completion ratio, or `nil` when the total size is unknown. |
| `DownloadError.invalidResponse` | The server response wasn't an `HTTPURLResponse`. |
| `DownloadError.serverError(statusCode:)` | The server responded with a non-2xx status code. |
| `DownloadError.cancelled` | The download was cancelled before producing a file. |

## Examples

### Basic download

```swift
import SwiftUtilsNetworking

let fileURL = try await DownloadManager.shared.download(
    URL(string: "https://example.com/report.pdf")!
)
try FileManager.default.moveItem(at: fileURL, to: finalDestination)
```

### Observing progress for a progress bar

```swift
let url = URL(string: "https://example.com/episode-42.mp4")!

for try await event in DownloadManager.shared.events(for: url) {
    switch event {
    case .progress(let written, let total):
        if let total {
            progressBar.progress = Float(written) / Float(total)
        } else {
            progressBar.isIndeterminate = true
        }
    case .completed(let fileURL):
        player.load(fileURL)
    }
}
```

### Saving under a custom filename

```swift
let fileURL = try await DownloadManager.shared.download(
    URL(string: "https://cdn.example.com/assets/v3/bundle.zip")!,
    filename: "latest-bundle.zip"
)
```

### Multiple views requesting the same download

Two screens that both display the same attachment can call `events(for:)` independently — only one network transfer happens, and both streams report the same progress and completion.

```swift
// Screen A
Task {
    for try await event in DownloadManager.shared.events(for: attachmentURL) {
        updatePreview(with: event)
    }
}

// Screen B, started moments later
Task {
    let fileURL = try await DownloadManager.shared.download(attachmentURL)
    showFullScreen(fileURL)
}
```

### A dedicated manager with a lower concurrency limit

Use a separate instance — rather than `.shared` — to cap how many transfers run at once for a bandwidth-sensitive feature, or to save files somewhere other than the default Caches directory.

```swift
let offlineSyncDownloader = DownloadManager(
    destinationDirectory: FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OfflineContent", isDirectory: true),
    maxConcurrentDownloads: 2
)

for asset in assetsToSync {
    Task { try await offlineSyncDownloader.download(asset.url, filename: asset.localName) }
}
```

### Cancelling and retrying

```swift
await DownloadManager.shared.cancel(url)

// Force a fresh download next time, discarding any cached file.
await DownloadManager.shared.forget(url)

do {
    let fileURL = try await DownloadManager.shared.download(url)
} catch DownloadError.serverError(let statusCode) {
    showError("Download failed with status \(statusCode)")
} catch is CancellationError {
    // user-initiated cancellation
} catch {
    showError("Download failed: \(error.localizedDescription)")
}
```

### Checking state before starting UI

```swift
if await DownloadManager.shared.isDownloading(url) {
    showProgressSpinner()
} else {
    showDownloadButton()
}
```
