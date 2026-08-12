# APIErrorMapper

Maps HTTP responses into typed, structured errors instead of raw `Data` — decodes RFC 7807 "Problem Details" bodies (or any custom `Decodable` error shape) and distinguishes client errors, server errors, transport failures, and undecodable bodies.

## API

| Type | Description |
|---|---|
| `ProblemDetails` | RFC 7807-conformant error body: `type`, `title`, `status`, `detail`, `instance` — all optional |
| `StructuredAPIError<Body>` | Typed error: `.clientError(status:body:)`, `.serverError(status:body:)`, `.undecodableBody(status:raw:)`, `.transport(URLError)` |
| `StructuredAPIError.statusCode` | The HTTP status code involved, or `nil` for `.transport` |
| `StructuredAPIError.errorDescription` | Human-readable message, preferring `ProblemDetails.detail`/`title` when available |
| `APIErrorMapper.isSuccess(_:)` | Returns `true` for status codes in `200..<300` |
| `APIErrorMapper.validate(data:response:as:decoder:)` | Throws `StructuredAPIError<Body>` for any non-2xx response |
| `APIErrorMapper.decode(_:from:response:errorType:decoder:)` | Validates, then decodes the success body in one call |
| `APIErrorMapper.mapTransportError(_:)` | Normalizes a caught `Error` (e.g. `URLError`) into `StructuredAPIError<Body>` |

## Examples

### Validate a response before decoding

```swift
import SwiftUtilsNetworking

let (data, response) = try await URLSession.shared.data(for: request)
try APIErrorMapper.validate(data: data, response: response, as: ProblemDetails.self)
let user = try JSONDecoder().decode(User.self, from: data)
```

### Validate and decode in one step

```swift
struct User: Decodable {
    let id: Int
    let name: String
}

let (data, response) = try await URLSession.shared.data(for: request)
let user = try APIErrorMapper.decode(User.self, from: data, response: response)
```

### Handling the typed error

```swift
do {
    let user = try APIErrorMapper.decode(User.self, from: data, response: response)
    print(user.name)
} catch let error as StructuredAPIError<ProblemDetails> {
    switch error {
    case .clientError(let status, let body):
        print("Client error \(status): \(body?.detail ?? "no detail")")
    case .serverError(let status, _):
        print("Server error \(status), consider retrying")
    case .undecodableBody(let status, let raw):
        print("Status \(status) with unparsable body: \(String(data: raw, encoding: .utf8) ?? "")")
    case .transport(let urlError):
        print("Network failure: \(urlError.localizedDescription)")
    }
}
```

### Using a custom error body shape

Many APIs don't follow RFC 7807. Supply your own `Decodable` type and `APIErrorMapper` will decode into it instead:

```swift
struct MyAPIError: Decodable, Sendable {
    let code: String
    let message: String
}

do {
    let user = try APIErrorMapper.decode(
        User.self,
        from: data,
        response: response,
        errorType: MyAPIError.self
    )
} catch let error as StructuredAPIError<MyAPIError> {
    if case .clientError(_, let body) = error, body?.code == "TOKEN_EXPIRED" {
        // trigger a re-auth flow
    }
}
```

### Normalizing transport errors alongside HTTP errors

```swift
func fetchUser() async -> Result<User, StructuredAPIError<ProblemDetails>> {
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let user = try APIErrorMapper.decode(User.self, from: data, response: response)
        return .success(user)
    } catch let error as StructuredAPIError<ProblemDetails> {
        return .failure(error)
    } catch {
        // No response was ever received (offline, timeout, cancelled, ...)
        return .failure(APIErrorMapper.mapTransportError(error))
    }
}
```

### Pairing with `NetworkRetrier`

```swift
let user: User = try await NetworkRetrier.execute(policy: .conservative) {
    let (data, response) = try await URLSession.shared.data(for: request)
    return try APIErrorMapper.decode(User.self, from: data, response: response)
}
```
