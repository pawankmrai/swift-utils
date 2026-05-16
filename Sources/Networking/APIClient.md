# APIClient

A lightweight, async/await HTTP client built on URLSession with automatic JSON coding.

## API

| Method | Description |
|---|---|
| `get(_:headers:)` | GET request with auto-decoded response |
| `post(_:body:headers:)` | POST request with encodable body |
| `request(_:method:body:headers:)` | Generic request for any HTTP method |
| `defaultHeaders` | Dictionary of headers applied to every request |

## Examples

```swift
import SwiftUtilsNetworking

let client = APIClient(baseURL: URL(string: "https://api.example.com")!)

// Simple GET
let users: [User] = try await client.get("/users")

// GET with custom headers
let profile: Profile = try await client.get("/me", headers: [
    "Authorization": "Bearer \(token)"
])

// POST with body
struct CreateUser: Encodable { let name: String; let email: String }
let newUser: User = try await client.post("/users", body: CreateUser(
    name: "Pawan",
    email: "pawan@example.com"
))

// Custom default headers
client.defaultHeaders["Authorization"] = "Bearer \(token)"

// Custom decoder/encoder
let customDecoder = JSONDecoder()
customDecoder.dateDecodingStrategy = .secondsSince1970

let client = APIClient(
    baseURL: URL(string: "https://api.example.com")!,
    decoder: customDecoder
)
```
