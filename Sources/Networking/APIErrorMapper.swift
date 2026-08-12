import Foundation

// MARK: - ProblemDetails

/// A machine-readable error body following [RFC 7807](https://datatracker.ietf.org/doc/html/rfc7807)
/// "Problem Details for HTTP APIs" — the most common structured error format
/// returned by modern JSON APIs.
///
/// All fields are optional per the spec, so partially-conforming backends still decode.
public struct ProblemDetails: Decodable, Sendable, Equatable {

    /// A URI reference identifying the problem type. Defaults to `"about:blank"` when absent.
    public let type: String?

    /// A short, human-readable summary of the problem type.
    public let title: String?

    /// The HTTP status code repeated in the body, if the server includes it.
    public let status: Int?

    /// A human-readable explanation specific to this occurrence of the problem.
    public let detail: String?

    /// A URI reference identifying this specific occurrence of the problem.
    public let instance: String?

    public init(type: String? = nil, title: String? = nil, status: Int? = nil, detail: String? = nil, instance: String? = nil) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.instance = instance
    }
}

// MARK: - StructuredAPIError

/// A typed error produced by mapping an HTTP response into a structured failure.
///
/// Distinguishes between client errors (4xx), server errors (5xx), transport-level
/// failures (no response at all), and cases where the error body couldn't be decoded.
public enum StructuredAPIError<Body: Decodable & Sendable>: Error, LocalizedError, Sendable {

    /// A 4xx response, with the decoded error body when available.
    case clientError(status: Int, body: Body?)

    /// A 5xx response, with the decoded error body when available.
    case serverError(status: Int, body: Body?)

    /// A non-2xx response whose body could not be decoded as `Body`, with the raw bytes for inspection.
    case undecodableBody(status: Int, raw: Data)

    /// The request never reached a server (offline, timed out, cancelled, DNS failure, etc).
    case transport(URLError)

    /// The HTTP status code involved in this error, if known.
    public var statusCode: Int? {
        switch self {
        case .clientError(let status, _), .serverError(let status, _), .undecodableBody(let status, _):
            return status
        case .transport:
            return nil
        }
    }

    public var errorDescription: String? {
        switch self {
        case .clientError(let status, let body), .serverError(let status, let body):
            if let problem = body as? ProblemDetails {
                return problem.detail ?? problem.title ?? "Request failed with status \(status)."
            }
            return "Request failed with status \(status)."
        case .undecodableBody(let status, let raw):
            let preview = String(data: raw.prefix(200), encoding: .utf8) ?? "<binary>"
            return "Request failed with status \(status) and an unrecognized error body: \(preview)"
        case .transport(let urlError):
            return urlError.localizedDescription
        }
    }
}

// MARK: - APIErrorMapper

/// Maps HTTP responses and their bodies into typed `StructuredAPIError` values, and validates
/// successful responses before they're decoded into your domain models.
///
/// Pairs naturally with `APIClient` or `RequestBuilder` — call `validate` (or `decode`)
/// right after a `URLSession` call to convert non-2xx responses into a structured error
/// instead of propagating raw `Data`.
///
/// ```swift
/// let (data, response) = try await URLSession.shared.data(for: request)
/// try APIErrorMapper.validate(data: data, response: response, as: ProblemDetails.self)
/// let user = try JSONDecoder().decode(User.self, from: data)
/// ```
public enum APIErrorMapper {

    /// Returns `true` if the status code is in the 2xx range.
    public static func isSuccess(_ statusCode: Int) -> Bool {
        (200..<300).contains(statusCode)
    }

    /// Validates a response, throwing a typed `StructuredAPIError<Body>` for any non-2xx status.
    ///
    /// - Parameters:
    ///   - data: The response body bytes.
    ///   - response: The `URLResponse` returned alongside `data`.
    ///   - bodyType: The `Decodable` type used to parse structured error bodies. Defaults to `ProblemDetails`.
    ///   - decoder: The decoder used to parse the error body. Defaults to a plain `JSONDecoder`.
    /// - Throws: `StructuredAPIError<Body>` if the response is not a 2xx HTTP response.
    public static func validate<Body: Decodable & Sendable>(
        data: Data,
        response: URLResponse,
        as bodyType: Body.Type = ProblemDetails.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !isSuccess(http.statusCode) else { return }

        let body = try? decoder.decode(Body.self, from: data)
        let status = http.statusCode

        if body == nil && !data.isEmpty {
            throw StructuredAPIError<Body>.undecodableBody(status: status, raw: data)
        }
        if (400..<500).contains(status) {
            throw StructuredAPIError<Body>.clientError(status: status, body: body)
        }
        throw StructuredAPIError<Body>.serverError(status: status, body: body)
    }

    /// Validates and decodes a successful response body in one step.
    ///
    /// - Parameters:
    ///   - type: The success-path `Decodable` model to parse.
    ///   - data: The response body bytes.
    ///   - response: The `URLResponse` returned alongside `data`.
    ///   - errorType: The `Decodable` type used for non-2xx error bodies. Defaults to `ProblemDetails`.
    ///   - decoder: The decoder used for both success and error bodies.
    /// - Returns: The decoded success model.
    /// - Throws: `StructuredAPIError<ErrorBody>` on a non-2xx response, or a `DecodingError` if the success body is malformed.
    public static func decode<T: Decodable, ErrorBody: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data,
        response: URLResponse,
        errorType: ErrorBody.Type = ProblemDetails.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try validate(data: data, response: response, as: errorType, decoder: decoder)
        return try decoder.decode(T.self, from: data)
    }

    /// Maps a transport-level failure (thrown before any response was received) into a `StructuredAPIError`.
    ///
    /// Pass errors caught around `URLSession` calls here to normalize them alongside
    /// response-based errors from `validate`/`decode`.
    public static func mapTransportError<Body: Decodable & Sendable>(_ error: Error) -> StructuredAPIError<Body> {
        if let apiError = error as? StructuredAPIError<Body> {
            return apiError
        }
        if let urlError = error as? URLError {
            return .transport(urlError)
        }
        return .transport(URLError(.unknown))
    }
}
