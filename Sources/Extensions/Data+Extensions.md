# Data+Extensions

Hex encoding, URL-safe Base64, hashing (SHA-256 / MD5), UTF-8 conversion, JSON pretty-printing, byte manipulation, and compression helpers for Swift's `Data` type.

## API

| Method / Property | Description |
|---|---|
| `init?(hex:)` | Create `Data` from a hex string (with optional `0x` prefix) |
| `hexString` | Lowercase hex string representation |
| `hexStringUppercased` | Uppercase hex string representation |
| `base64URLEncoded` | URL-safe Base64 encoded string (RFC 4648 §5) |
| `init?(base64URLEncoded:)` | Create `Data` from a URL-safe Base64 string |
| `sha256` | SHA-256 hash as `Data` |
| `md5` | MD5 hash as `Data` |
| `utf8String` | Interpret bytes as a UTF-8 string |
| `init(utf8:)` | Create `Data` from a UTF-8 string |
| `prettyJSON` | Pretty-printed JSON string, or `nil` if not valid JSON |
| `readableByteCount` | Human-readable file size (e.g., "2.4 MB") |
| `reversed` | New `Data` with bytes in reverse order |
| `safeSlice(_:)` | Bounds-clamped byte range slice |
| `compressed(using:)` | Compress with zlib, lzfse, lz4, or lzma |
| `decompressed(using:)` | Decompress with the matching algorithm |

## Examples

```swift
import SwiftUtilsExtensions

// Hex encoding & decoding
let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
print(bytes.hexString)            // "deadbeef"
print(bytes.hexStringUppercased)  // "DEADBEEF"

let decoded = Data(hex: "0x48656C6C6F")!
print(decoded.utf8String!)  // "Hello"

// URL-safe Base64 (great for JWTs and URL parameters)
let payload = Data("{\"sub\":\"1234\"}".utf8)
let token = payload.base64URLEncoded  // No +, /, or = characters
let restored = Data(base64URLEncoded: token)!

// Hashing
let message = Data("hello".utf8)
print(message.sha256.hexString)
// "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

let checksum = message.md5.hexString
// "5d41402abc4b2a76b9719d911017c592"

// UTF-8 convenience
let data = Data(utf8: "Swift is great!")
print(data.utf8String!)  // "Swift is great!"

// Pretty-print JSON responses
let json = Data(#"{"name":"Pawan","scores":[98,85,92]}"#.utf8)
if let pretty = json.prettyJSON {
    print(pretty)
    // {
    //   "name" : "Pawan",
    //   "scores" : [98, 85, 92]
    // }
}

// Byte helpers
let imageData = Data(count: 2_500_000)
print(imageData.readableByteCount)  // "2.5 MB"

let header = largeData.safeSlice(0..<4)   // won't crash on short data
let flipped = Data([0x01, 0x02, 0x03]).reversed  // [0x03, 0x02, 0x01]

// Compression round-trip
let original = Data(String(repeating: "Hello! ", count: 1000).utf8)
let compressed = try original.compressed(using: .zlib)
print(compressed.readableByteCount)  // much smaller

let restored = try compressed.decompressed(using: .zlib)
assert(restored == original)
```
