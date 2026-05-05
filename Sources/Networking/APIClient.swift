import Foundation

/// A lightweight, async/await-based API client for making HTTP requests.
///
/// Usage:
/// ```swift
/// let client = APIClient(baseURL: URL(string: "https://api.example.com")!)
/// let users: [User] = try await client.get("/users")
/// ```
public final class APIClient {

    /// The base URL for all requests
    public let baseURL: URL

    /// Shared URLSession used for requests
    private let session: URLSession

    /// Default JSON decoder
    private let decoder: JSONDecoder

    /// Default JSON encoder
    private let encoder: JSONEncoder

    /// Default headers applied to every request
    public var defaultHeaders: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json"
    ]

    /// Creates a new API client with the given base URL.
    /// - Parameters:
    ///   - baseURL: The base URL for all requests
    ///   - session: A custom URLSession (defaults to `.shared`)
    ///   - decoder: A custom JSONDecoder (defaults to one with `.convertFromSnakeCase` key strategy)
    ///   - encoder: A custom JSONEncoder (defaults to one with `.convertToSnakeCase` key strategy)
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder? = nil,
        encoder: JSONEncoder? = nil
    ) {
        self.baseURL = baseURL
        self.session = session

        let defaultDecoder = JSONDecoder()
        defaultDecoder.keyDecodingStrategy = .convertFromSnakeCase
        defaultDecoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder ?? defaultDecoder

        let defaultEncoder = JSONEncoder()
        defaultEncoder.keyEncodingStrategy = .convertToSnakeCase
        defaultEncoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder ?? defaultEncoder
    }

    // MARK: - Public Methods

    /// Performs a GET request and decodes the response.
    /// - Parameters:
    ///   - path: The endpoint path (appended to baseURL)
    ///   - queryItems: Optional query parameters
    ///   - headers: Additional headers for this request
    /// - Returns: Decoded response of type `T`
    public func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", queryItems: queryItems, headers: headers)
        return try await execute(request)
    }

    /// Performs a POST request with an encodable body and decodes the response.
    /// - Parameters:
    ///   - path: The endpoint path (appended to baseURL)
    ///   - body: The request body (must be `Encodable`)
    ///   - headers: Additional headers for this request
    /// - Returns: Decoded response of type `T`
    public func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> T {
        var request = try buildRequest(path: path, method: "POST", headers: headers)
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    /// Performs a PUT request with an encodable body and decodes the response.
    public func put<T: Decodable, B: Encodable>(
        _ path: String,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> T {
        var request = try buildRequest(path: path, method: "PUT", headers: headers)
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    /// Performs a DELETE request and decodes the response.
    public func delete<T: Decodable>(
        _ path: String,
        headers: [String: String]? = nil
    ) async throws -> T {
        let request = try buildRequest(path: path, method: "DELETE", headers: headers)
        return try await execute(request)
    }

    // MARK: - Private Methods

    private func buildRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL(path)
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Error Types

/// Errors that can occur during API requests
public enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid URL for path: \(path)"
        case .invalidResponse:
            return "Invalid response received"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }

    /// Attempts to decode the error response body as the given type
    public func decodeErrorBody<T: Decodable>(as type: T.Type, decoder: JSONDecoder = JSONDecoder()) -> T? {
        guard case .httpError(_, let data) = self else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
