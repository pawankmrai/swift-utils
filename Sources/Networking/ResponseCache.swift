import Foundation

// MARK: - CacheEntry

/// A single cached value paired with storage and expiration metadata.
///
/// This is an internal storage representation — `ResponseCache`'s public API
/// always deals in plain `Value`s, never in `CacheEntry` itself.
struct CacheEntry<Value: Codable & Sendable>: Codable, Sendable {

    /// The cached value.
    let value: Value

    /// When the value was stored.
    let storedAt: Date

    /// When the value expires, or `nil` if it never expires.
    let expiresAt: Date?

    /// Whether the entry has passed its expiration date.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

// MARK: - ResponseCache

/// An actor-based cache for API responses with in-memory and on-disk persistence.
///
/// `ResponseCache` stores `Codable` values keyed by string, with optional
/// per-entry TTL (time-to-live) expiration. Use it to avoid redundant network
/// requests for data that doesn't change often, such as configuration,
/// profile data, or paginated list responses.
///
/// Each cache is namespaced to its own subdirectory under the app's Caches
/// directory, so multiple caches for different response types never collide.
///
/// ```swift
/// let cache = ResponseCache<UserProfile>(namespace: "user-profiles", defaultTTL: 300)
///
/// let profile = try await cache.value(for: "user-42") {
///     try await api.fetchProfile(id: "user-42")
/// }
/// ```
public actor ResponseCache<Value: Codable & Sendable> {

    private var memoryCache: [String: CacheEntry<Value>] = [:]
    private let diskURL: URL?
    private let defaultTTL: TimeInterval?

    /// Creates a new response cache.
    /// - Parameters:
    ///   - namespace: A unique name for this cache, used as its disk subdirectory.
    ///   - persistToDisk: Whether entries should also be written to disk. Default `true`.
    ///   - defaultTTL: Default time-to-live (in seconds) applied when `store` doesn't specify one. `nil` means entries never expire by default.
    public init(namespace: String, persistToDisk: Bool = true, defaultTTL: TimeInterval? = nil) {
        self.defaultTTL = defaultTTL
        if persistToDisk,
           let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.diskURL = caches.appendingPathComponent("ResponseCache/\(namespace)", isDirectory: true)
        } else {
            self.diskURL = nil
        }
    }

    /// Returns the cached value for `key`, or `nil` if missing or expired.
    /// Falls back to disk if the value isn't in memory yet.
    public func value(for key: String) -> Value? {
        if let entry = memoryCache[key] {
            guard !entry.isExpired else {
                invalidate(key)
                return nil
            }
            return entry.value
        }
        guard let entry = loadFromDisk(key) else { return nil }
        guard !entry.isExpired else {
            invalidate(key)
            return nil
        }
        memoryCache[key] = entry
        return entry.value
    }

    /// Returns the cached value for `key` if present and fresh, otherwise
    /// runs `fetch`, stores its result, and returns it.
    /// - Parameters:
    ///   - key: The cache key.
    ///   - ttl: Time-to-live override for this entry. Falls back to `defaultTTL`.
    ///   - fetch: An async throwing closure that produces a fresh value on a cache miss.
    public func value(for key: String, ttl: TimeInterval? = nil, fetch: @Sendable () async throws -> Value) async rethrows -> Value {
        if let cached = value(for: key) { return cached }
        let fresh = try await fetch()
        store(fresh, for: key, ttl: ttl)
        return fresh
    }

    /// Stores `value` under `key`, replacing any existing entry.
    /// - Parameters:
    ///   - value: The value to cache.
    ///   - key: The cache key.
    ///   - ttl: Time-to-live override for this entry. Falls back to `defaultTTL`. `nil` (with no default) never expires.
    public func store(_ value: Value, for key: String, ttl: TimeInterval? = nil) {
        let effectiveTTL = ttl ?? defaultTTL
        let entry = CacheEntry(
            value: value,
            storedAt: Date(),
            expiresAt: effectiveTTL.map { Date().addingTimeInterval($0) }
        )
        memoryCache[key] = entry
        saveToDisk(entry, key: key)
    }

    /// Removes the entry for `key` from memory and disk.
    public func invalidate(_ key: String) {
        memoryCache[key] = nil
        removeFromDisk(key)
    }

    /// Removes all entries from memory and disk.
    public func removeAll() {
        memoryCache.removeAll()
        if let diskURL {
            try? FileManager.default.removeItem(at: diskURL)
        }
    }

    /// Evicts all currently-expired entries from memory (and their disk copies).
    /// - Returns: The number of entries evicted.
    @discardableResult
    public func evictExpired() -> Int {
        let expiredKeys = memoryCache.filter { $0.value.isExpired }.keys
        for key in expiredKeys { invalidate(key) }
        return expiredKeys.count
    }

    /// The number of entries currently held in memory.
    public var count: Int { memoryCache.count }

    // MARK: Disk I/O

    private func fileURL(for key: String) -> URL? {
        guard let diskURL else { return nil }
        let safeName = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return diskURL.appendingPathComponent(safeName)
    }

    private func saveToDisk(_ entry: CacheEntry<Value>, key: String) {
        guard let fileURL = fileURL(for: key) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Disk persistence is best-effort; the in-memory cache remains authoritative.
        }
    }

    private func loadFromDisk(_ key: String) -> CacheEntry<Value>? {
        guard let fileURL = fileURL(for: key),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CacheEntry<Value>.self, from: data)
    }

    private func removeFromDisk(_ key: String) {
        guard let fileURL = fileURL(for: key) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
