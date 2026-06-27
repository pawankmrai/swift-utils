import Foundation

/// A builder for assembling `multipart/form-data` HTTP request bodies.
///
/// `MultipartFormDataBuilder` produces RFC 7578-compliant bodies for mixed
/// text-field and file-upload forms — the format required by most "upload a
/// photo," "submit a profile with an avatar," or "attach a document" APIs.
/// It pairs naturally with `RequestBuilder` or a plain `URLRequest`.
///
/// ```swift
/// let form = MultipartFormDataBuilder()
///     .addField(name: "title", value: "Vacation Photo")
///     .addField(name: "userId", value: "42")
///     .addFile(name: "photo", fileName: "beach.jpg", mimeType: "image/jpeg", data: imageData)
///
/// var request = URLRequest(url: uploadURL)
/// request.httpMethod = "POST"
/// form.apply(to: &request)
///
/// let (data, response) = try await URLSession.shared.data(for: request)
/// ```
public final class MultipartFormDataBuilder {

    // MARK: - Errors

    /// Errors that can be thrown while building a multipart body.
    public enum BuilderError: Error, LocalizedError {
        /// Encoding an `Encodable` value as a JSON part failed.
        case jsonEncodingFailed(Error)
        /// Reading file contents from disk for a file part failed.
        case fileReadFailed(URL, Error)

        public var errorDescription: String? {
            switch self {
            case .jsonEncodingFailed(let error):
                return "Failed to encode JSON part: \(error.localizedDescription)"
            case .fileReadFailed(let url, let error):
                return "Failed to read file at \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private State

    /// The boundary string separating parts. Unique per builder by default.
    public let boundary: String

    private var parts: [Data] = []

    // MARK: - Initialiser

    /// Creates a new, empty multipart form builder.
    /// - Parameter boundary: A custom boundary string. Defaults to a random,
    ///   collision-resistant value — most callers should leave this as-is.
    public init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    // MARK: - Builder Methods

    /// Adds a plain text field, e.g. a form input or JSON-free parameter.
    @discardableResult
    public func addField(name: String, value: String) -> Self {
        appendPart(
            headers: [("Content-Disposition", "form-data; name=\"\(name)\"")],
            body: Data(value.utf8)
        )
        return self
    }

    /// Adds an in-memory file part, such as image data captured from the camera
    /// or a picker, without writing it to disk first.
    /// - Parameters:
    ///   - name: The form field name the server expects.
    ///   - fileName: The filename reported to the server (e.g. `"photo.jpg"`).
    ///   - mimeType: The part's `Content-Type`. Defaults to `"application/octet-stream"`.
    ///   - data: The raw file bytes.
    @discardableResult
    public func addFile(
        name: String,
        fileName: String,
        mimeType: String = "application/octet-stream",
        data: Data
    ) -> Self {
        appendPart(
            headers: [
                ("Content-Disposition", "form-data; name=\"\(name)\"; filename=\"\(fileName)\""),
                ("Content-Type", mimeType),
            ],
            body: data
        )
        return self
    }

    /// Adds a file part by reading its contents from disk.
    /// - Parameters:
    ///   - name: The form field name the server expects.
    ///   - fileURL: The on-disk location of the file to upload.
    ///   - mimeType: The part's `Content-Type`. Defaults to a best-effort guess
    ///     based on the file extension (see `MultipartFormDataBuilder.mimeType(forPathExtension:)`).
    /// - Throws: `BuilderError.fileReadFailed` if the file cannot be read.
    @discardableResult
    public func addFile(name: String, fileURL: URL, mimeType: String? = nil) throws -> Self {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw BuilderError.fileReadFailed(fileURL, error)
        }
        let resolvedMimeType = mimeType ?? Self.mimeType(forPathExtension: fileURL.pathExtension)
        return addFile(name: name, fileName: fileURL.lastPathComponent, mimeType: resolvedMimeType, data: data)
    }

    /// Adds an `Encodable` value as a JSON file part — handy for APIs that
    /// expect a `metadata` or `payload` field alongside an uploaded file.
    /// - Parameters:
    ///   - name: The form field name the server expects.
    ///   - value: The value to encode as JSON.
    ///   - encoder: The encoder to use. Defaults to a plain `JSONEncoder()`.
    /// - Throws: `BuilderError.jsonEncodingFailed` if encoding fails.
    @discardableResult
    public func addJSON<T: Encodable>(name: String, value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Self {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw BuilderError.jsonEncodingFailed(error)
        }
        return addFile(name: name, fileName: "\(name).json", mimeType: "application/json", data: data)
    }

    // MARK: - Build

    /// The value to set as the request's `Content-Type` header.
    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// Assembles all added parts into the final request body.
    /// Calling this multiple times is safe and always returns the same bytes.
    public func build() -> Data {
        var body = Data()
        for part in parts {
            body.append(part)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// Builds the body and applies it to `request`, setting `Content-Type`
    /// and `Content-Length` headers in the process.
    public func apply(to request: inout URLRequest) {
        let body = build()
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = body
    }

    // MARK: - Private Helpers

    private func appendPart(headers: [(String, String)], body: Data) {
        var part = Data()
        part.append(Data("--\(boundary)\r\n".utf8))
        for (field, value) in headers {
            part.append(Data("\(field): \(value)\r\n".utf8))
        }
        part.append(Data("\r\n".utf8))
        part.append(body)
        part.append(Data("\r\n".utf8))
        parts.append(part)
    }

    // MARK: - MIME Type Lookup

    /// A small built-in lookup table from common file extensions to MIME types.
    /// Used as the default when uploading a file by URL without specifying one.
    public static func mimeType(forPathExtension `extension`: String) -> String {
        switch `extension`.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "heic":        return "image/heic"
        case "webp":        return "image/webp"
        case "pdf":         return "application/pdf"
        case "json":        return "application/json"
        case "txt":         return "text/plain"
        case "csv":         return "text/csv"
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        case "mp3":         return "audio/mpeg"
        case "m4a":         return "audio/m4a"
        case "zip":         return "application/zip"
        default:            return "application/octet-stream"
        }
    }
}

// MARK: - URLRequest Convenience

public extension URLRequest {

    /// Creates a ready-to-send `multipart/form-data` request from a builder.
    ///
    /// ```swift
    /// let request = URLRequest.multipartFormData(url: uploadURL) { form in
    ///     form.addField(name: "userId", value: "42")
    ///     form.addFile(name: "avatar", fileName: "me.jpg", mimeType: "image/jpeg", data: avatarData)
    /// }
    /// ```
    /// - Parameters:
    ///   - url: The destination URL.
    ///   - method: The HTTP method. Defaults to `"POST"`.
    ///   - configure: A closure that adds fields and files to the builder.
    static func multipartFormData(
        url: URL,
        method: String = "POST",
        configure: (MultipartFormDataBuilder) -> Void
    ) -> URLRequest {
        let builder = MultipartFormDataBuilder()
        configure(builder)
        var request = URLRequest(url: url)
        request.httpMethod = method
        builder.apply(to: &request)
        return request
    }
}
