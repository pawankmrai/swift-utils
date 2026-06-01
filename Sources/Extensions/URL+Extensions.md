# URL+Extensions

Convenient helpers for constructing, inspecting, and manipulating URLs in iOS apps.

## API

| Property / Method | Returns | Description |
|---|---|---|
| `queryParameter(_:)` | `String?` | Get a query parameter value by name |
| `appendingQueryParameters(_:)` | `URL?` | Append query parameters, preserving existing ones |
| `removingQueryParameter(_:)` | `URL?` | Remove a query parameter by name |
| `queryDictionary` | `[String: String]` | All query parameters as a dictionary |
| `fileName` | `String` | Last path component without extension |
| `appendingPathComponents(_:)` | `URL` | Append multiple path components at once |
| `isSecure` | `Bool` | Whether URL uses HTTPS or WSS |
| `hasFileExtension(in:)` | `Bool` | Check extension against a list (case-insensitive) |
| `isImageURL` | `Bool` | Whether URL points to a common image format |
| `pathSegments` | `[String]` | Path components without "/" separators |
| `deepLink(scheme:host:path:query:)` | `URL?` | Build a deep link URL from parts |
| `masked(with:)` | `String` | URL string with query values replaced by a mask |

## Examples

```swift
import SwiftUtilsExtensions

// Query parameter access
let url = URL(string: "https://api.example.com/search?q=swift&page=2")!
url.queryParameter("q")     // "swift"
url.queryParameter("page")  // "2"
url.queryDictionary          // ["q": "swift", "page": "2"]

// Adding and removing parameters
let withToken = url.appendingQueryParameters(["token": "abc123"])
// https://api.example.com/search?q=swift&page=2&token=abc123

let withoutPage = url.removingQueryParameter("page")
// https://api.example.com/search?q=swift

// Path helpers
let base = URL(string: "https://api.example.com/v2")!
let endpoint = base.appendingPathComponents(["users", "123", "posts"])
// https://api.example.com/v2/users/123/posts

URL(string: "https://cdn.example.com/images/photo.jpg")!.fileName  // "photo"

// Security check
URL(string: "https://example.com")!.isSecure  // true
URL(string: "http://example.com")!.isSecure   // false

// File type detection
let imageURL = URL(string: "https://cdn.example.com/banner.webp")!
imageURL.isImageURL                              // true
imageURL.hasFileExtension(in: ["pdf", "doc"])     // false

// Deep link construction
let link = URL.deepLink(scheme: "myapp", host: "product", path: "/123", query: ["ref": "home"])
// myapp://product/123?ref=home

// Path segment parsing
URL(string: "myapp://settings/notifications/email")!.pathSegments
// ["settings", "notifications", "email"]

// Safe logging — mask sensitive query values
let apiURL = URL(string: "https://api.com/data?token=secret&user=42")!
apiURL.masked()  // "https://api.com/data?token=***&user=***"
```
