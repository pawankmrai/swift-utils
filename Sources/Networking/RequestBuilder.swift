import Foundation

/// A fluent, chainable builder for constructing `URLRequest` instances.
///
/// `RequestBuilder` makes it easy to assemble HTTP requests in a readable,
/// composable way — including method, headers, query parameters, body,
/// timeout, and cache policy — before executing them via `URLSession`.
///
/// Usage:
/// ```swift
/// let request = try RequestBuilder(url: "https://api.example.com/users")
///     .method(.post)
///     .header("Authorization", value: "Bearer \(token)")
///     .query("page", value: "2")
///     .body(newUser)        // Encodable
///     .timeout(30)
///     .build()
/// ```
public final class RequestBuilder {

    // MARK: - HTTP Method

    /// Standard HTTP methods.
    public enum HTTPMethod: String {
        case get     = "GET"
        case post    = "POST"
        case put     = "PUT"
        case patch   = "PATCH"
        case delete  = "DELETE"
        case head    = "HEAD"
        case options = "OPTIONS"
    }

    // MARK: - Errors

    /// Errors that can be thrown by `RequestBuilder`.
    public enum BuilderError: Error, LocalizedError {
        /// The base URL string is invalid.
        case invalidURL(String)
        /// Body encoding failed.
        case encodingFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .invalidURL(let string):
                return "Invalid URL: \(string)"
            case .encodingFailed(let error):
                return "Body encoding failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private State

    private var url: URL
    private var httpMethod: HTTPMethod = .get
    private var headers: [String: String] = [:]
    private var queryItems: [URLQueryItem] = []
    private var httpBody: Data?
    private var timeoutInterval: TimeInterval = 60
    private var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    private var encoder: JSONEncoder = JSONEncoder()

    // MARK: - Initialisers

    /// Creates a builder from a `URL`.
    public init(url: URL) {
        self.url = url
    }

    /// Creates a builder from a URL string.
    /// - Throws: `BuilderError.invalidURL` if the string cannot be parsed.
    public init(url string: String) throws {
        guard let url = URL(string: string) else {
            throw BuilderError.invalidURL(string)
        }
        self.url = url
    }

    // MARK: - Builder Methods

    /// Sets the HTTP method. Defaults to `.get`.
    @discardableResult
    public func method(_ method: HTTPMethod) -> Self {
        httpMethod = method
        return self
    }

    /// Adds a single request header. Replaces any existing value for the same field.
    @discardableResult
    public func header(_ field: String, value: String) -> Self {
        headers[field] = value
        return self
    }

    /// Adds multiple headers at once.
    @discardableResult
    public func headers(_ newHeaders: [String: String]) -> Self {
        newHeaders.forEach { headers[$0.key] = $0.value }
        return self
    }

    /// Appends a URL query parameter.
    @discardableResult
    public func query(_ name: String, value: String?) -> Self {
        queryItems.append(URLQueryItem(name: name, value: value))
        return self
    }

    /// Appends multiple query parameters from a dictionary.
    @discardableResult
    public func queryParameters(_ params: [String: String?]) -> Self {
        params.forEach { queryItems.append(URLQueryItem(name: $0.key, value: $0.value)) }
        return self
    }

    /// Sets the request body to raw `Data`.
    @discardableResult
    public func body(data: Data) -> Self {
        httpBody = data
        return self
    }

    /// Encodes an `Encodable` value as JSON and sets it as the request body.
    /// Also sets `Content-Type: application/json` if not already present.
    /// - Throws: `BuilderError.encodingFailed` if encoding fails.
    @discardableResult
    public func body<T: Encodable>(_ value: T, encoder: JSONEncoder? = nil) throws -> Self {
        let enc = encoder ?? self.encoder
        do {
            httpBody = try enc.encode(value)
        } catch {
            throw BuilderError.encodingFailed(error)
        }
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }
        return self
    }

    /// Sets the request timeout in seconds. Defaults to 60.
    @discardableResult
    public func timeout(_ seconds: TimeInterval) -> Self {
        timeoutInterval = seconds
        return self
    }

    /// Sets the cache policy. Defaults to `.useProtocolCachePolicy`.
    @discardableResult
    public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Self {
        cachePolicy = policy
        return self
    }

    /// Replaces the default `JSONEncoder` used for body encoding.
    @discardableResult
    public func jsonEncoder(_ enc: JSONEncoder) -> Self {
        encoder = enc
        return self
    }

    // MARK: - Build

    /// Assembles and returns the configured `URLRequest`.
    /// - Throws: `BuilderError` if the URL with query items cannot be formed.
    public func build() throws -> URLRequest {
        var finalURL = url
        if !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let existing = components?.queryItems ?? []
            components?.queryItems = existing + queryItems
            guard let resolved = components?.url else {
                throw BuilderError.invalidURL(url.absoluteString + " (query assembly failed)")
            }
            finalURL = resolved
        }

        var request = URLRequest(
            url: finalURL,
            cachePolicy: cachePolicy,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = httpMethod.rawValue
        request.httpBody = httpBody
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    // MARK: - Convenience Execute

    /// Builds the request and executes it with the given `URLSession`.
    /// Returns raw `(Data, HTTPURLResponse)`.
    ///
    /// - Parameter session: The session to use. Defaults to `.shared`.
    /// - Throws: Network or URL errors, plus any `BuilderError`.
    @discardableResult
    public func execute(
        session: URLSession = .shared
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try build()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    /// Builds the request, executes it, and decodes the response body as `T`.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode into.
    ///   - decoder: JSON decoder to use. Defaults to a plain `JSONDecoder()`.
    ///   - session: The session to use. Defaults to `.shared`.
    /// - Throws: Network, decoding, or URL errors.
    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = JSONDecoder(),
        session: URLSession = .shared
    ) async throws -> T {
        let (data, _) = try await execute(session: session)
        return try decoder.decode(type, from: data)
    }
}
