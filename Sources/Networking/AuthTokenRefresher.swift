//
//  AuthTokenRefresher.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-24.
//

import Foundation

// MARK: - AuthToken

/// A snapshot of an OAuth-style access token together with its expiry.
public struct AuthToken: Sendable, Equatable {

    /// The bearer token to attach to outgoing requests.
    public let accessToken: String

    /// When the server considers this token expired.
    public let expiresAt: Date

    /// Creates a token snapshot.
    public init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// Whether the token is still safe to use, with `leeway` seconds of
    /// headroom subtracted so a token doesn't expire mid-flight.
    public func isValid(leeway: TimeInterval = 30) -> Bool {
        expiresAt.timeIntervalSinceNow > leeway
    }
}

// MARK: - AuthTokenError

/// Errors surfaced by ``AuthTokenRefresher``.
public enum AuthTokenError: Error, LocalizedError, Sendable {

    /// The `refresh` closure threw while exchanging for a new token.
    case refreshFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .refreshFailed(let underlying):
            return "Failed to refresh access token: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - AuthTokenRefresher

/// Actor that owns an app's current access token, refreshes it on demand,
/// and guarantees that concurrent callers never trigger more than one
/// refresh at a time.
///
/// Hand it a `refresh` closure that knows how to exchange a refresh token
/// (or re-authenticate) for a new ``AuthToken``. `AuthTokenRefresher` takes
/// care of caching, expiry checks, single-flight de-duplication of
/// concurrent refreshes, and transparent 401-triggered retries — the pieces
/// that are easy to get wrong when wiring OAuth into a networking layer by
/// hand.
///
/// ```swift
/// let refresher = AuthTokenRefresher {
///     try await authService.refreshAccessToken(using: currentRefreshToken)
/// }
///
/// // Anywhere in the app, at any concurrency level — only one network
/// // refresh ever happens even if ten requests race for an expired token.
/// let (data, response) = try await refresher.execute(request, using: .shared)
/// ```
public actor AuthTokenRefresher {

    /// Exchanges for a fresh ``AuthToken``. Called at most once at a time,
    /// no matter how many callers are waiting on a token concurrently.
    public typealias RefreshHandler = @Sendable () async throws -> AuthToken

    private var currentToken: AuthToken?
    private var refreshTask: Task<AuthToken, Error>?
    private let refresh: RefreshHandler
    private let leeway: TimeInterval
    private let headerField: String
    private let headerPrefix: String

    /// Creates a refresher.
    /// - Parameters:
    ///   - initialToken: A token to seed the cache with, e.g. one restored
    ///     from the keychain at launch.
    ///   - leeway: Seconds of headroom subtracted from a token's expiry when
    ///     deciding whether it's still usable. Defaults to 30.
    ///   - headerField: The HTTP header ``authorize(_:)`` writes to.
    ///     Defaults to `"Authorization"`.
    ///   - headerPrefix: Prefix written before the token value. Defaults to
    ///     `"Bearer "`.
    ///   - refresh: Performs the actual token exchange (network call to a
    ///     token endpoint, re-authentication, etc).
    public init(
        initialToken: AuthToken? = nil,
        leeway: TimeInterval = 30,
        headerField: String = "Authorization",
        headerPrefix: String = "Bearer ",
        refresh: @escaping RefreshHandler
    ) {
        self.currentToken = initialToken
        self.leeway = leeway
        self.headerField = headerField
        self.headerPrefix = headerPrefix
        self.refresh = refresh
    }

    // MARK: Token access

    /// Returns a token guaranteed to be valid for at least `leeway` seconds,
    /// refreshing first if the cached token is missing or stale.
    ///
    /// Safe to call concurrently: if a refresh is already in flight, every
    /// caller awaits that same refresh instead of starting a new one.
    public func validToken() async throws -> AuthToken {
        if let token = currentToken, token.isValid(leeway: leeway) {
            return token
        }
        return try await performRefresh()
    }

    /// Forces the next call to ``validToken()`` to refresh, even though the
    /// cached token still looks unexpired locally.
    ///
    /// Call this after a server rejects a token with 401 despite it
    /// appearing valid client-side (clock skew, server-side revocation,
    /// password change on another device, etc).
    public func invalidate() {
        currentToken = nil
    }

    /// Manually seeds the cache, e.g. immediately after login or when
    /// restoring a session from persistent storage.
    public func setToken(_ token: AuthToken) {
        currentToken = token
        refreshTask = nil
    }

    /// The cached token, if any, without triggering a refresh or validity
    /// check. Useful for diagnostics/logging.
    public var cachedToken: AuthToken? {
        currentToken
    }

    // MARK: Request helpers

    /// Returns a copy of `request` with the authorization header set to a
    /// currently valid token, refreshing first if needed.
    public func authorize(_ request: URLRequest) async throws -> URLRequest {
        let token = try await validToken()
        var authorized = request
        authorized.setValue(headerPrefix + token.accessToken, forHTTPHeaderField: headerField)
        return authorized
    }

    /// Authorizes and executes `request` on `session`, transparently
    /// refreshing the token and retrying **once** if the server responds
    /// with 401 Unauthorized.
    ///
    /// If the retried request also 401s, that response is returned as-is
    /// rather than looping — callers should treat a second 401 as a genuine
    /// auth failure (e.g. sign the user out).
    public func execute(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> (Data, URLResponse) {
        let authorized = try await authorize(request)
        let (data, response) = try await session.data(for: authorized)

        guard let http = response as? HTTPURLResponse, http.statusCode == 401 else {
            return (data, response)
        }

        invalidate()
        let retried = try await authorize(request)
        return try await session.data(for: retried)
    }

    // MARK: Private

    private func performRefresh() async throws -> AuthToken {
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<AuthToken, Error> {
            do {
                return try await refresh()
            } catch {
                throw AuthTokenError.refreshFailed(underlying: error)
            }
        }
        refreshTask = task
        defer { refreshTask = nil }

        let token = try await task.value
        currentToken = token
        return token
    }
}
