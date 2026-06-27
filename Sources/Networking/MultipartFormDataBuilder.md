# MultipartFormDataBuilder

A builder for assembling RFC 7578-compliant `multipart/form-data` request bodies — the format required by most photo, avatar, and document upload APIs.

## API

| Type | Description |
|---|---|
| `MultipartFormDataBuilder` | Builder that accumulates text and file parts and assembles them into a request body |
| `MultipartFormDataBuilder.init(boundary:)` | Creates a builder, optionally with a custom boundary string |
| `MultipartFormDataBuilder.addField(name:value:)` | Adds a plain text field |
| `MultipartFormDataBuilder.addFile(name:fileName:mimeType:data:)` | Adds an in-memory file part |
| `MultipartFormDataBuilder.addFile(name:fileURL:mimeType:)` | Adds a file part by reading it from disk; throws on read failure |
| `MultipartFormDataBuilder.addJSON(name:value:encoder:)` | Encodes an `Encodable` value as a JSON file part |
| `MultipartFormDataBuilder.contentType` | The `Content-Type` header value (includes the boundary) |
| `MultipartFormDataBuilder.build()` | Assembles all parts into the final `Data` body |
| `MultipartFormDataBuilder.apply(to:)` | Builds the body and applies it plus headers to a `URLRequest` |
| `MultipartFormDataBuilder.mimeType(forPathExtension:)` | Static lookup from file extension to common MIME type |
| `MultipartFormDataBuilder.BuilderError` | `jsonEncodingFailed`, `fileReadFailed` |
| `URLRequest.multipartFormData(url:method:configure:)` | Convenience that builds a ready-to-send multipart `URLRequest` |

## Examples

### Basic upload with a text field and an in-memory file

```swift
import SwiftUtilsNetworking

let form = MultipartFormDataBuilder()
    .addField(name: "title", value: "Vacation Photo")
    .addField(name: "userId", value: "42")
    .addFile(name: "photo", fileName: "beach.jpg", mimeType: "image/jpeg", data: imageData)

var request = URLRequest(url: uploadURL)
request.httpMethod = "POST"
form.apply(to: &request)

let (data, response) = try await URLSession.shared.data(for: request)
```

### One-line request with the `URLRequest` convenience

```swift
let request = URLRequest.multipartFormData(url: uploadURL) { form in
    form.addField(name: "userId", value: "42")
    form.addFile(name: "avatar", fileName: "me.jpg", mimeType: "image/jpeg", data: avatarData)
}

let (_, response) = try await URLSession.shared.data(for: request)
```

### Uploading a file directly from disk

`addFile(name:fileURL:)` reads the file and guesses its MIME type from the
extension when one isn't supplied.

```swift
let form = MultipartFormDataBuilder()
try form.addFile(name: "document", fileURL: pdfURL) // mimeType inferred as "application/pdf"
```

### Attaching JSON metadata alongside a file

Useful for APIs that expect a `multipart` request with one part being a file
and another being structured metadata.

```swift
struct UploadMetadata: Encodable {
    let albumId: String
    let takenAt: Date
}

let form = MultipartFormDataBuilder()
try form.addJSON(name: "metadata", value: UploadMetadata(albumId: "abc", takenAt: .now))
form.addFile(name: "photo", fileName: "beach.jpg", mimeType: "image/jpeg", data: imageData)
```

### Combining with `RequestBuilder`

```swift
let form = MultipartFormDataBuilder()
form.addFile(name: "file", fileName: "report.csv", mimeType: "text/csv", data: csvData)

var request = try RequestBuilder(url: "https://api.example.com/reports")
    .method(.post)
    .header("Authorization", value: "Bearer \(token)")
    .build()
form.apply(to: &request)

let (data, response) = try await URLSession.shared.data(for: request)
```

### Custom boundary and MIME type lookup

```swift
let form = MultipartFormDataBuilder(boundary: "MyAppBoundary-\(UUID().uuidString)")
let mimeType = MultipartFormDataBuilder.mimeType(forPathExtension: "heic") // "image/heic"
form.addFile(name: "photo", fileName: "scan.heic", mimeType: mimeType, data: heicData)
```
