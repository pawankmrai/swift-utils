# FileManagerHelper

A lightweight wrapper around `FileManager` that provides a clean, typed API for reading, writing, listing, copying, and moving files across the standard iOS sandbox directories.

## API

| Type / Method | Description |
|---|---|
| `FileDirectory` | Enum for `.documents`, `.caches`, `.temporary`, `.applicationSupport`, `.custom(URL)` |
| `FileManagerError` | Typed errors: `fileNotFound`, `fileAlreadyExists`, `encodingFailed`, `decodingFailed`, `underlyingError` |
| `FileAttributes` | Value type with `size: Int`, `creationDate: Date?`, `modificationDate: Date?` |
| `init(fileManager:encoder:decoder:)` | Inject custom `FileManager` or JSON coders; defaults to `.default` + ISO 8601 |
| `directoryURL(for:)` | Resolve and auto-create the URL for a `FileDirectory` |
| `createDirectory(named:in:)` | Create a named subdirectory; returns its URL |
| `write(_:to:in:overwrite:)` | Encode a `Codable` value as JSON and persist it atomically |
| `writeData(_:to:in:overwrite:)` | Write raw `Data` atomically; optionally guard against overwrite |
| `read(from:in:)` | Decode a `Codable` value from a JSON file |
| `readData(from:in:)` | Read raw `Data` from a file |
| `exists(_:in:)` | Check whether a file exists |
| `attributes(of:in:)` | Retrieve `FileAttributes` for a file |
| `contentsOfDirectory(_:)` | List URLs of all items directly inside a directory |
| `move(_:from:to:newFilename:)` | Move (and optionally rename) a file between directories |
| `copy(_:from:to:newFilename:)` | Copy (and optionally rename) a file between directories |
| `delete(_:in:)` | Delete a file; no-op if it doesn't exist |
| `clearDirectory(_:)` | Delete all contents of a directory without removing the directory itself |

## Examples

### Persist and restore a Codable model

```swift
import SwiftUtilsStorage

struct UserProfile: Codable {
    let username: String
    let score: Int
}

let helper = FileManagerHelper()
let profile = UserProfile(username: "pawan", score: 9800)

// Write to Documents
try helper.write(profile, to: "profile.json", in: .documents)

// Read back
let loaded: UserProfile = try helper.read(from: "profile.json", in: .documents)
print(loaded.username) // "pawan"
```

### Cache raw data (e.g. a downloaded image)

```swift
let imageData: Data = // ... downloaded from network

// Store in Caches (OS can purge when low on storage)
try helper.writeData(imageData, to: "avatar_\(userID).jpg", in: .caches)

// Later, check before downloading again
if try helper.exists("avatar_\(userID).jpg", in: .caches) {
    let cached = try helper.readData(from: "avatar_\(userID).jpg", in: .caches)
    // use cached data
}
```

### Write to a scratch file in tmp, then promote to Documents

```swift
// Write draft to tmp
try helper.writeData(draftData, to: "draft.json", in: .temporary)

// When user confirms, move to Documents
try helper.move("draft.json", from: .temporary, to: .documents)
```

### Organise files into subdirectories

```swift
// Create a logs subdirectory inside Application Support
let logsURL = try helper.createDirectory(named: "logs", in: .applicationSupport)

// Write a log file there
try helper.writeData(logData, to: "2026-06-07.log", in: .custom(logsURL))

// List all log files
let logFiles = try helper.contentsOfDirectory(.custom(logsURL))
logFiles.forEach { print($0.lastPathComponent) }
```

### Inspect file metadata

```swift
let attrs = try helper.attributes(of: "profile.json", in: .documents)
print("Size: \(attrs.size) bytes")
if let modified = attrs.modificationDate {
    print("Last modified: \(modified)")
}
```

### Clear the Caches directory

```swift
// Purge everything in Caches (e.g. on low-memory warning)
try helper.clearDirectory(.caches)
```

### Use a custom directory

```swift
// Point to any URL — useful for shared App Group containers
let sharedContainer = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.myapp")!

let sharedHelper = FileManagerHelper()
try sharedHelper.writeData(payload, to: "widget_data.json", in: .custom(sharedContainer))
```

### Guard against accidental overwrites

```swift
do {
    try helper.write(config, to: "config.json", in: .documents, overwrite: false)
} catch FileManagerError.fileAlreadyExists(let url) {
    print("Config already exists at \(url.path); skipping write.")
}
```
