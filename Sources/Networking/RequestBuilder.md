# RequestBuilder

A fluent, chainable builder for constructing `URLRequest` instances. Compose HTTP requests method-by-method — setting the verb, headers, query parameters, JSON body, timeout, and cache policy — then either `build()` a plain `URLRequest` or call `execute()` / `decode()` to fire it immediately.

## API

| Method / Property | Description |
|---|---|
| `init(url: URL)` | Create a builder from a `URL` |
| `init(url: String) throws` | Create a builder from a URL string; throws `BuilderError.invalidURL` if unparseable |
| `method(_:)` | Set the HTTP method (`.get`, `.post`, `.put`, `.patch`, `.delete`, …) |
| `header(_:value:)` | Add or replace a single header field |
| `headers(_:)` | Merge a dictionary of headers |
| `query(_:value:)` | Append a URL query parameter |
| `queryParameters(_:)` | Append multiple query parameters from a dictionary |
| `body(data:)` | Set the request body from raw `Data` |
| `body(_:encoder:) throws` | JSON-encode an `Encodable` value and set it as the body; sets `Content-Type: application/json` automatically |
| `timeout(_:)` | Set request timeout in seconds (default: 60) |
| `cachePolicy(_:)` | Set `URLRequest.CachePolicy` (default: `.useProtocolCachePolicy`) |
| `jsonEncoder(_:)` | Replace the default `JSONEncoder` used for body encoding |
| `build() throws` | Assemble and return the `URLRequest` |
| `execute(session:) async throws` | Build and execute; returns `(Data, HTTPURLResponse)` |
| `decode(_:decoder:session:) async throws` | Build, execute, and JSON-decode the response into a `Decodable` type |
| `BuilderError.invalidURL` | Thrown when the URL string cannot be parsed or query assembly fails |
| `BuilderError.encodingFailed` | Thrown when body encoding fails |

## Examples

```swift
import SwiftUtilsNetworking

// ── Simple GET ──────────────────────────────────────────────────────────────
let request = try RequestBuilder(url: "https://api.example.com/users")
    .query("page", value: "2")
    .query("per_page", value: "20")
    .header("Accept", value: "application/json")
    .timeout(15)
    .build()

// ── POST with Encodable body ─────────────────────────────────────────────────
struct NewUser: Encodable {
    let name: String
    let email: String
}

let (data, response) = try await RequestBuilder(url: "https://api.example.com/users")
    .method(.post)
    .header("Authorization", value: "Bearer \(token)")
    .body(NewUser(name: "Alice", email: "alice@example.com"))
    .timeout(30)
    .execute()

print(response.statusCode)   // 201

// ── Decode response directly ─────────────────────────────────────────────────
struct User: Decodable { let id: Int; let name: String }

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let user: User = try await RequestBuilder(url: "https://api.example.com/users/42")
    .header("Authorization", value: "Bearer \(token)")
    .decode(User.self, decoder: decoder)

// ── PUT / PATCH ──────────────────────────────────────────────────────────────
struct ProfileUpdate: Encodable { let bio: String }

let _ = try await RequestBuilder(url: "https://api.example.com/users/42")
    .method(.patch)
    .header("Authorization", value: "Bearer \(token)")
    .body(ProfileUpdate(bio: "iOS developer"))
    .execute()

// ── DELETE ───────────────────────────────────────────────────────────────────
let _ = try await RequestBuilder(url: "https://api.example.com/users/42")
    .method(.delete)
    .header("Authorization", value: "Bearer \(token)")
    .execute()

// ── Multiple query params from a dict ────────────────────────────────────────
let searchRequest = try RequestBuilder(url: "https://api.example.com/search")
    .queryParameters(["q": "swift", "sort": "stars", "order": "desc"])
    .build()

// ── Custom encoder (snake_case keys) ─────────────────────────────────────────
let enc = JSONEncoder()
enc.keyEncodingStrategy = .convertToSnakeCase

let _ = try await RequestBuilder(url: "https://api.example.com/profile")
    .method(.put)
    .jsonEncoder(enc)
    .body(ProfileUpdate(bio: "Updated"))
    .execute()

// ── No-cache policy ──────────────────────────────────────────────────────────
let freshRequest = try RequestBuilder(url: "https://api.example.com/status")
    .cachePolicy(.reloadIgnoringLocalCacheData)
    .build()

// ── Reuse with a custom URLSession ───────────────────────────────────────────
let config = URLSessionConfiguration.default
config.httpAdditionalHeaders = ["X-App-Version": "2.1.0"]
let session = URLSession(configuration: config)

let (body, _) = try await RequestBuilder(url: "https://api.example.com/feed")
    .query("limit", value: "50")
    .execute(session: session)
```
