# AuthTokenRefresher

An actor that owns an app's current OAuth-style access token, refreshes it on demand, and guarantees that concurrent callers never trigger more than one refresh at a time.

Hand it a `refresh` closure that knows how to exchange a refresh token (or re-authenticate) for a new `AuthToken`. `AuthTokenRefresher` takes care of caching, expiry checks with configurable leeway, single-flight de-duplication of concurrent refreshes, and transparent 401-triggered retries — the pieces that are easy to get wrong when wiring token refresh into a networking layer by hand.

If ten requests race for an expired token at the same moment, only one refresh call goes out; every other caller awaits that same in-flight refresh and receives the same result.

## API

| Type / Method | Description |
|---|---|
| `AuthToken(accessToken:expiresAt:)` | A snapshot of an access token and its expiry |
| `AuthToken.isValid(leeway:) -> Bool` | Whether the token is still usable, with `leeway` seconds of headroom subtracted |
| `AuthTokenRefresher(initialToken:leeway:headerField:headerPrefix:refresh:)` | Creates a refresher backed by a token-exchange closure |
| `validToken() async throws -> AuthToken` | Returns a valid token, refreshing (and de-duplicating concurrent refreshes) if needed |
| `invalidate()` | Forces the next `validToken()` call to refresh, even if the cached token looks unexpired |
| `setToken(_:)` | Manually seeds the cache, e.g. after login or session restore |
| `cachedToken: AuthToken?` | The cached token without triggering a refresh or validity check |
| `authorize(_:) async throws -> URLRequest` | Returns a copy of a request with the authorization header set to a valid token |
| `execute(_:using:) async throws -> (Data, URLResponse)` | Authorizes and runs a request, retrying once on a 401 with a freshly refreshed token |
| `AuthTokenError.refreshFailed(underlying:)` | Thrown when the `refresh` closure itself throws |

## Examples

### Basic setup

```swift
let refresher = AuthTokenRefresher {
    try await authService.refreshAccessToken(using: currentRefreshToken)
}

// Seed it with a token restored from the keychain at launch, if any.
if let saved = try? keychain.readToken() {
    await refresher.setToken(saved)
}
```

### Authorizing requests through an APIClient-style layer

```swift
final class SecureAPI {
    private let refresher: AuthTokenRefresher
    private let session: URLSession

    init(refresher: AuthTokenRefresher, session: URLSession = .shared) {
        self.refresher = refresher
        self.session = session
    }

    func fetchProfile() async throws -> UserProfile {
        var request = URLRequest(url: URL(string: "https://api.example.com/me")!)
        request.httpMethod = "GET"

        // Attaches a valid Authorization header, refreshing first if the
        // cached token has expired.
        let authorized = try await refresher.authorize(request)
        let (data, response) = try await session.data(for: authorized)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }
}
```

### Transparent 401 retry with `execute(_:using:)`

```swift
let refresher = AuthTokenRefresher {
    try await authService.refreshAccessToken(using: currentRefreshToken)
}

var request = URLRequest(url: profileURL)

// If the server rejects the current token with 401 — expired sooner than
// expected, revoked, clock skew — the refresher refreshes once and retries
// automatically. Callers only see the final response.
let (data, response) = try await refresher.execute(request, using: .shared)

if let http = response as? HTTPURLResponse, http.statusCode == 401 {
    // Refresh itself didn't resolve it — the refresh token is likely dead.
    await signOut()
}
```

### Concurrent requests share a single refresh

```swift
let refresher = AuthTokenRefresher {
    try await authService.refreshAccessToken(using: currentRefreshToken)
}

// Screen loads that fire five requests in parallel against an expired
// token only cause one network call to the token endpoint — the other
// four requests await that same refresh before proceeding.
async let profile = api.fetchProfile()
async let feed = api.fetchFeed()
async let notifications = api.fetchNotifications()
async let settings = api.fetchSettings()
async let billing = api.fetchBillingStatus()

let results = try await (profile, feed, notifications, settings, billing)
```

### Forcing a refresh after a suspicious failure

```swift
// The cached token looked valid client-side but the server disagreed
// (e.g. it was revoked from another device).
await refresher.invalidate()
let token = try await refresher.validToken()
```

### Custom header field and prefix

```swift
// Some APIs use a non-standard scheme instead of "Authorization: Bearer …".
let refresher = AuthTokenRefresher(
    headerField: "X-Api-Token",
    headerPrefix: "Token "
) {
    try await authService.refreshAccessToken(using: currentRefreshToken)
}

let authorized = try await refresher.authorize(request)
// authorized.value(forHTTPHeaderField: "X-Api-Token") == "Token <accessToken>"
```

### Handling refresh failures

```swift
do {
    let token = try await refresher.validToken()
    use(token)
} catch let AuthTokenError.refreshFailed(underlying) {
    // The refresh endpoint itself failed — surface a re-login prompt.
    print("Could not refresh session: \(underlying.localizedDescription)")
    await promptReauthentication()
}
```
