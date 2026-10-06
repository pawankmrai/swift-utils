# JSONValue

A type-safe, `Codable` enum that represents arbitrary JSON — for payloads whose shape isn't known at compile time.

Strongly-typed `Codable` models are the right default, but real APIs often include a loosely-typed corner: analytics `properties`, a remote-config blob, webhook bodies, or a free-form `metadata` field. `[String: Any]` throws away type safety and isn't `Codable`. `JSONValue` keeps everything `Hashable`, `Sendable`, and `Codable`, and adds literal syntax, typed accessors, dot-path lookup, deep merge, and bridging to and from your own models.

## API

| Type / Method | Description |
|---|---|
| `JSONValue` | `.null`, `.bool(Bool)`, `.number(Double)`, `.string(String)`, `.array([JSONValue])`, `.object([String: JSONValue])` |
| `init(data:)` | Parses raw JSON bytes (top-level fragments allowed) |
| `init(encoding:encoder:)` | Converts any `Encodable` model into a `JSONValue` |
| `decode(_:decoder:) -> T` | Decodes the value into a concrete `Decodable` type |
| `data(prettyPrinted:sortedKeys:) -> Data` | Serializes back to JSON bytes |
| `merging(_:) -> JSONValue` | Deep-merges objects recursively; for other conflicts the overlay wins |
| `subscript(key:) -> JSONValue?` | Object member lookup |
| `subscript(index:) -> JSONValue?` | Bounds-safe array element lookup |
| `subscript(path:) -> JSONValue?` | Dot-path lookup such as `"data.items.0.title"` |
| `stringValue`, `doubleValue`, `intValue`, `boolValue` | Typed scalar accessors (`nil` on type mismatch) |
| `arrayValue`, `objectValue`, `isNull` | Container accessors and null check |
| `description` | Compact, sorted-key JSON text for logging |
| Literal conformances | `nil`, `Bool`, `Int`, `Double`, `String`, array and dictionary literals |

> `intValue` returns a value only when the number is integral. Numbers are stored as `Double`, so integers above 2^53 lose precision — keep large IDs as strings.

## Examples

### Parsing an unknown response

```swift
import SwiftUtilsNetworking

let (data, _) = try await URLSession.shared.data(from: url)
let json = try JSONValue(data: data)

let title = json[path: "data.items.0.title"]?.stringValue ?? "Untitled"
let count = json["meta"]?["total"]?.intValue ?? 0
let isBeta = json[path: "flags.beta"]?.boolValue == true
```

### A free-form field inside a typed model

```swift
struct AnalyticsEvent: Codable {
    let name: String
    let timestamp: Date
    let properties: JSONValue
}

let event = AnalyticsEvent(
    name: "checkout_completed",
    timestamp: .now,
    properties: [
        "amount": 49.99,
        "currency": "INR",
        "items": ["sku-1", "sku-2"],
        "coupon": nil
    ]
)
let body = try JSONEncoder().encode(event)
```

### Building request bodies with literals

```swift
let payload: JSONValue = [
    "query": "swift",
    "filters": ["language": "en", "minStars": 100],
    "page": 1
]

var request = URLRequest(url: searchURL)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try payload.data()
```

### Layered remote config with deep merge

```swift
let defaults: JSONValue = [
    "theme": ["primary": "#0066FF", "cornerRadius": 12],
    "paywall": ["enabled": false]
]
let remote = try JSONValue(data: remoteConfigData)   // e.g. {"paywall":{"enabled":true}}

let config = defaults.merging(remote)
config[path: "paywall.enabled"]?.boolValue     // true  (from remote)
config[path: "theme.cornerRadius"]?.intValue   // 12    (kept from defaults)
```

### Converting to and from your own models

```swift
struct Profile: Codable { let id: Int; let name: String }

// Model → JSONValue (e.g. to patch a field before sending)
var json = try JSONValue(encoding: Profile(id: 1, name: "Pawan"))
json = json.merging(["name": "Pawan K"])

// JSONValue → Model
let profile: Profile = try json.decode()
```

### Pretty-printing for debug logs

```swift
let json = try JSONValue(data: data)
print(json)                                         // {"a":1,"b":[true,null]}
print(String(decoding: try json.data(prettyPrinted: true), as: UTF8.self))
```

### Pattern matching

```swift
switch json["status"] {
case .string(let s)?:  print("status:", s)
case .number(let n)?:  print("code:", n)
case .null?, nil:      print("no status")
default:               print("unexpected:", json["status"]!)
}
```
