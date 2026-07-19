import Foundation

/// A thread-safe, in-memory **Least-Recently-Used** cache with a fixed
/// capacity and optional per-entry time-to-live (TTL).
///
/// Unlike ``CodableStore`` (disk-backed) or ``ResponseCache`` (network
/// response focused), `LRUCache` is a general-purpose in-memory cache for
/// any `Key`/`Value` pair — decoded models, computed layout metrics, thumbnail
/// bitmaps, parsed JSON, or anything else that's expensive to recompute but
/// cheap to hold in memory for a while.
///
/// When the cache is full, inserting a new entry evicts the **least recently
/// used** one first. Reading a value via ``value(forKey:)`` counts as a use
/// and moves that entry to the most-recently-used position, so hot entries
/// naturally survive while cold ones get evicted.
///
/// Entries can optionally expire after a fixed ``defaultTTL`` (set at init)
/// or a per-entry TTL passed to ``setValue(_:forKey:ttl:)``. Expired entries
/// are treated as absent and lazily purged on access.
///
/// `LRUCache` is implemented as an `actor`, so every operation is
/// automatically serialized — safe to share across concurrent callers
/// without any external locking.
///
/// ## Quick start
/// ```swift
/// let cache = LRUCache<URL, UIImage>(capacity: 100)
/// await cache.setValue(image, forKey: url)
/// if let cached = await cache.value(forKey: url) {
///     imageView.image = cached
/// }
/// ```
public actor LRUCache<Key: Hashable & Sendable, Value: Sendable> {

    /// A node in the internal doubly-linked usage list.
    private final class Node {
        let key: Key
        var value: Value
        var expiresAt: Date?
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value, expiresAt: Date?) {
            self.key = key
            self.value = value
            self.expiresAt = expiresAt
        }
    }

    private var nodes: [Key: Node] = [:]
    private var head: Node?   // most recently used
    private var tail: Node?   // least recently used

    /// Maximum number of entries the cache holds before evicting.
    public private(set) var capacity: Int

    /// Default lifetime applied to entries that don't specify their own TTL.
    /// `nil` means entries never expire on their own (subject only to LRU eviction).
    public let defaultTTL: TimeInterval?

    private let clock: @Sendable () -> Date

    /// Creates an LRU cache.
    ///
    /// - Parameters:
    ///   - capacity: Maximum number of entries. Must be at least 1.
    ///   - defaultTTL: Default expiration interval applied to entries that
    ///     don't specify their own. Defaults to `nil` (no expiration).
    ///   - clock: Injectable time source, primarily for testing. Defaults to `Date.init`.
    public init(capacity: Int, defaultTTL: TimeInterval? = nil, clock: @escaping @Sendable () -> Date = Date.init) {
        precondition(capacity >= 1, "LRUCache capacity must be at least 1")
        self.capacity = capacity
        self.defaultTTL = defaultTTL
        self.clock = clock
    }

    // MARK: - Reads

    /// The value for `key`, or `nil` if absent or expired.
    ///
    /// A successful lookup promotes the entry to most-recently-used.
    public func value(forKey key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        if let expiresAt = node.expiresAt, expiresAt <= clock() {
            remove(node)
            return nil
        }
        moveToFront(node)
        return node.value
    }

    /// Whether `key` is present and not expired, without affecting recency order.
    public func contains(_ key: Key) -> Bool {
        guard let node = nodes[key] else { return false }
        if let expiresAt = node.expiresAt, expiresAt <= clock() {
            remove(node)
            return false
        }
        return true
    }

    /// The number of live (non-expired) entries currently stored.
    public var count: Int {
        nodes.count
    }

    /// All non-expired values, ordered from most- to least-recently-used.
    /// Does not affect recency order (unlike ``value(forKey:)``).
    public func allValues() -> [Value] {
        purgeExpired()
        var result: [Value] = []
        var node = head
        while let current = node {
            result.append(current.value)
            node = current.next
        }
        return result
    }

    // MARK: - Writes

    /// Inserts or updates the value for `key`, promoting it to
    /// most-recently-used. Evicts the least-recently-used entry first if the
    /// cache is at capacity.
    ///
    /// - Parameters:
    ///   - value: The value to store.
    ///   - key: The key to store it under.
    ///   - ttl: Per-entry expiration override. Defaults to ``defaultTTL``.
    /// - Returns: The evicted value, if inserting this entry caused an eviction.
    @discardableResult
    public func setValue(_ value: Value, forKey key: Key, ttl: TimeInterval? = nil) -> Value? {
        let expiresAt = (ttl ?? defaultTTL).map { clock().addingTimeInterval($0) }

        if let existing = nodes[key] {
            existing.value = value
            existing.expiresAt = expiresAt
            moveToFront(existing)
            return nil
        }

        let node = Node(key: key, value: value, expiresAt: expiresAt)
        nodes[key] = node
        insertAtFront(node)

        guard nodes.count > capacity, let lru = tail else { return nil }
        remove(lru)
        return lru.value
    }

    /// Removes and returns the value for `key`, if present (expired or not).
    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        guard let node = nodes[key] else { return nil }
        remove(node)
        return node.value
    }

    /// Removes every entry.
    public func removeAll() {
        nodes.removeAll()
        head = nil
        tail = nil
    }

    /// Changes the maximum capacity, evicting least-recently-used entries
    /// immediately if the new capacity is smaller than the current count.
    public func setCapacity(_ newCapacity: Int) {
        precondition(newCapacity >= 1, "LRUCache capacity must be at least 1")
        capacity = newCapacity
        while nodes.count > capacity, let lru = tail {
            remove(lru)
        }
    }

    /// Removes all expired entries. Called automatically by ``allValues()``;
    /// exposed for callers who want to proactively reclaim memory (e.g. on a
    /// memory-warning notification).
    public func purgeExpired() {
        let now = clock()
        var node = head
        while let current = node {
            let next = current.next
            if let expiresAt = current.expiresAt, expiresAt <= now {
                remove(current)
            }
            node = next
        }
    }

    // MARK: - Linked list bookkeeping

    private func insertAtFront(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func moveToFront(_ node: Node) {
        guard head !== node else { return }
        unlink(node)
        insertAtFront(node)
    }

    private func unlink(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node { head = node.next }
        if tail === node { tail = node.prev }
        node.prev = nil
        node.next = nil
    }

    private func remove(_ node: Node) {
        unlink(node)
        nodes[node.key] = nil
    }
}
