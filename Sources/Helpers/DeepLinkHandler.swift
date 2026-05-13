import Foundation

// MARK: - DeepLinkHandler

/// A composable deep link routing system for iOS applications.
///
/// `DeepLinkHandler` provides a declarative way to register URL patterns and
/// route incoming deep links to the appropriate handlers. It supports path
/// parameters, query parameter extraction, and fallback handling.
///
/// ## Usage
/// ```swift
/// let router = DeepLinkHandler()
///
/// router.register("product/:id") { context in
///     let productId = context.pathParameters["id"]!
///     // Navigate to product detail
/// }
///
/// router.register("user/:userId/posts/:postId") { context in
///     let userId = context.pathParameters["userId"]!
///     let postId = context.pathParameters["postId"]!
///     // Navigate to specific post
/// }
///
/// // Handle an incoming URL
/// let url = URL(string: "myapp://product/42?ref=push")!
/// router.handle(url) // Routes to product handler with id="42", queryParams=["ref": "push"]
/// ```
public final class DeepLinkHandler {
    
    // MARK: - Types
    
    /// Context passed to route handlers containing parsed URL information.
    public struct RouteContext {
        /// The original URL that was matched.
        public let url: URL
        
        /// Path parameters extracted from the URL pattern (e.g., `:id` → `"42"`).
        public let pathParameters: [String: String]
        
        /// Query parameters from the URL (e.g., `?ref=push` → `["ref": "push"]`).
        public let queryParameters: [String: String]
        
        /// The scheme of the URL (e.g., `"myapp"`).
        public let scheme: String?
    }
    
    /// A handler closure that processes a matched route.
    public typealias RouteHandler = (RouteContext) -> Void
    
    /// Result of attempting to handle a URL.
    public enum HandleResult {
        case matched(pattern: String)
        case noMatch
        case invalidURL
    }
    
    // MARK: - Private Types
    
    private struct Route {
        let pattern: String
        let segments: [PatternSegment]
        let handler: RouteHandler
    }
    
    private enum PatternSegment {
        case literal(String)
        case parameter(String)
        case wildcard
    }
    
    // MARK: - Properties
    
    private var routes: [Route] = []
    private var fallbackHandler: RouteHandler?
    private var allowedSchemes: Set<String>?
    
    // MARK: - Initialization
    
    /// Creates a new deep link handler.
    /// - Parameter allowedSchemes: Optional set of URL schemes to accept. If nil, all schemes are accepted.
    public init(allowedSchemes: Set<String>? = nil) {
        self.allowedSchemes = allowedSchemes?.map { $0.lowercased() }.reduce(into: Set<String>()) { $0.insert($1) }
    }
    
    // MARK: - Registration
    
    /// Registers a URL pattern with an associated handler.
    ///
    /// Patterns support:
    /// - Literal segments: `"product/details"`
    /// - Named parameters: `"product/:id"` (captures the segment value)
    /// - Wildcards: `"product/*"` (matches any single segment)
    ///
    /// - Parameters:
    ///   - pattern: The URL path pattern to match against.
    ///   - handler: The closure to execute when the pattern matches.
    public func register(_ pattern: String, handler: @escaping RouteHandler) {
        let segments = parsePattern(pattern)
        let route = Route(pattern: pattern, segments: segments, handler: handler)
        routes.append(route)
    }
    
    /// Sets a fallback handler for URLs that don't match any registered pattern.
    /// - Parameter handler: The closure to execute for unmatched URLs.
    public func setFallback(_ handler: @escaping RouteHandler) {
        fallbackHandler = handler
    }
    
    // MARK: - Handling
    
    /// Attempts to handle a URL by matching it against registered patterns.
    ///
    /// Routes are evaluated in registration order. The first matching pattern wins.
    ///
    /// - Parameter url: The URL to handle.
    /// - Returns: A `HandleResult` indicating whether the URL was matched.
    @discardableResult
    public func handle(_ url: URL) -> HandleResult {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .invalidURL
        }
        
        // Check scheme restriction
        if let allowedSchemes = allowedSchemes,
           let scheme = components.scheme?.lowercased(),
           !allowedSchemes.contains(scheme) {
            return .noMatch
        }
        
        let pathSegments = extractPathSegments(from: components)
        let queryParams = extractQueryParameters(from: components)
        
        for route in routes {
            if let pathParams = matchRoute(route.segments, against: pathSegments) {
                let context = RouteContext(
                    url: url,
                    pathParameters: pathParams,
                    queryParameters: queryParams,
                    scheme: components.scheme
                )
                route.handler(context)
                return .matched(pattern: route.pattern)
            }
        }
        
        // Try fallback
        if let fallback = fallbackHandler {
            let context = RouteContext(
                url: url,
                pathParameters: [:],
                queryParameters: queryParams,
                scheme: components.scheme
            )
            fallback(context)
        }
        
        return .noMatch
    }
    
    /// Checks if a URL would match any registered pattern without executing the handler.
    /// - Parameter url: The URL to test.
    /// - Returns: `true` if the URL matches a registered pattern.
    public func canHandle(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        
        if let allowedSchemes = allowedSchemes,
           let scheme = components.scheme?.lowercased(),
           !allowedSchemes.contains(scheme) {
            return false
        }
        
        let pathSegments = extractPathSegments(from: components)
        
        return routes.contains { route in
            matchRoute(route.segments, against: pathSegments) != nil
        }
    }
    
    /// Returns all registered patterns.
    public var registeredPatterns: [String] {
        routes.map(\.pattern)
    }
    
    // MARK: - Private Helpers
    
    private func parsePattern(_ pattern: String) -> [PatternSegment] {
        pattern
            .split(separator: "/")
            .map { segment in
                let s = String(segment)
                if s.hasPrefix(":") {
                    return .parameter(String(s.dropFirst()))
                } else if s == "*" {
                    return .wildcard
                } else {
                    return .literal(s)
                }
            }
    }
    
    private func extractPathSegments(from components: URLComponents) -> [String] {
        // For URLs like "myapp://product/42", host is "product" and path is "/42"
        // For URLs like "https://example.com/product/42", host is "example.com" and path is "/product/42"
        var segments: [String] = []
        
        if let host = components.host, !host.isEmpty,
           components.scheme != "https" && components.scheme != "http" {
            segments.append(host)
        }
        
        let pathSegments = components.path
            .split(separator: "/")
            .map(String.init)
        
        segments.append(contentsOf: pathSegments)
        return segments
    }
    
    private func extractQueryParameters(from components: URLComponents) -> [String: String] {
        var params: [String: String] = [:]
        components.queryItems?.forEach { item in
            params[item.name] = item.value ?? ""
        }
        return params
    }
    
    private func matchRoute(_ pattern: [PatternSegment], against path: [String]) -> [String: String]? {
        guard pattern.count == path.count else { return nil }
        
        var parameters: [String: String] = [:]
        
        for (segment, value) in zip(pattern, path) {
            switch segment {
            case .literal(let expected):
                if expected.lowercased() != value.lowercased() {
                    return nil
                }
            case .parameter(let name):
                parameters[name] = value
            case .wildcard:
                continue
            }
        }
        
        return parameters
    }
}
