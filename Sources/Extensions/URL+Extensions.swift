import Foundation

// MARK: - URL+Extensions

/// Convenient helpers for constructing, inspecting, and manipulating URLs.
extension URL {

    // MARK: - Query Parameter Helpers

    /// Returns the value of a query parameter by name, or `nil` if not present.
    ///
    /// ```swift
    /// let url = URL(string: "https://example.com?page=2&lang=en")!
    /// url.queryParameter("page")  // "2"
    /// ```
    public func queryParameter(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    /// Returns a new URL with the given query parameters appended.
    /// Existing parameters are preserved.
    ///
    /// ```swift
    /// let url = URL(string: "https://api.example.com/search")!
    /// let withParams = url.appendingQueryParameters(["q": "swift", "page": "1"])
    /// ```
    public func appendingQueryParameters(_ parameters: [String: String]) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        for (key, value) in parameters {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url
    }

    /// Returns a new URL with the specified query parameter removed.
    public func removingQueryParameter(_ name: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = components.queryItems?.filter { $0.name != name }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }
        return components.url
    }

    /// All query parameters as a dictionary. Duplicate keys use the last value.
    public var queryDictionary: [String: String] {
        guard let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        return items.reduce(into: [:]) { result, item in
            result[item.name] = item.value ?? ""
        }
    }

    // MARK: - Path Helpers

    /// The file name without extension (last path component minus its extension).
    ///
    /// ```swift
    /// URL(string: "https://cdn.example.com/images/photo.jpg")!.fileName  // "photo"
    /// ```
    public var fileName: String {
        deletingPathExtension().lastPathComponent
    }

    /// Returns a new URL with the given path components appended.
    ///
    /// ```swift
    /// let base = URL(string: "https://api.example.com/v2")!
    /// let endpoint = base.appendingPathComponents(["users", "123", "posts"])
    /// // https://api.example.com/v2/users/123/posts
    /// ```
    public func appendingPathComponents(_ components: [String]) -> URL {
        components.reduce(self) { $0.appendingPathComponent($1) }
    }

    // MARK: - Validation & Classification

    /// Whether the URL uses a secure scheme (HTTPS or WSS).
    public var isSecure: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "wss"
    }

    /// Whether the URL points to a file with one of the given extensions (case-insensitive).
    ///
    /// ```swift
    /// let url = URL(string: "https://cdn.example.com/doc.PDF")!
    /// url.hasFileExtension(in: ["pdf", "doc"])  // true
    /// ```
    public func hasFileExtension(in extensions: [String]) -> Bool {
        let ext = pathExtension.lowercased()
        return extensions.contains { $0.lowercased() == ext }
    }

    /// Whether the URL appears to point to an image based on its extension.
    public var isImageURL: Bool {
        hasFileExtension(in: ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff"])
    }

    // MARK: - Deep Link Helpers

    /// Extracts path segments as an array, filtering empty strings.
    ///
    /// ```swift
    /// URL(string: "myapp://settings/notifications/email")!.pathSegments
    /// // ["settings", "notifications", "email"]
    /// ```
    public var pathSegments: [String] {
        pathComponents.filter { $0 != "/" }
    }

    /// Creates a URL from a deep-link scheme, host, and optional path/query.
    ///
    /// ```swift
    /// let link = URL.deepLink(scheme: "myapp", host: "product", path: "/123", query: ["ref": "home"])
    /// // myapp://product/123?ref=home
    /// ```
    public static func deepLink(
        scheme: String,
        host: String,
        path: String? = nil,
        query: [String: String]? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path ?? ""
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    // MARK: - Masking

    /// Returns the URL string with query parameter values replaced by a mask.
    /// Useful for logging URLs without leaking tokens or PII.
    ///
    /// ```swift
    /// url.masked()  // "https://api.example.com/search?token=***&q=***"
    /// ```
    public func masked(with mask: String = "***") -> String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        components.queryItems = components.queryItems?.map {
            URLQueryItem(name: $0.name, value: mask)
        }
        return components.string ?? absoluteString
    }
}
