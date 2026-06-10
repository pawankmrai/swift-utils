import Foundation

// MARK: - Event Protocol

/// A trackable analytics event with a name and optional properties.
public protocol AnalyticsEvent {
    /// The event name sent to analytics backends.
    var name: String { get }
    /// Key-value properties attached to this event.
    var properties: [String: Any] { get }
}

/// Default empty properties for events that carry no extra data.
public extension AnalyticsEvent {
    var properties: [String: Any] { [:] }
}

// MARK: - Backend Protocol

/// Conform to this protocol to route analytics events to any backend
/// (Firebase, Amplitude, Mixpanel, a custom server, etc.).
public protocol AnalyticsBackend {
    /// Called by `AnalyticsTracker` when an event is ready to send.
    /// - Parameters:
    ///   - event: The event to record.
    ///   - mergedProperties: Event properties merged with global properties.
    func track(event: any AnalyticsEvent, mergedProperties: [String: Any])

    /// Called when a user identity is established.
    func identify(userId: String, traits: [String: Any])

    /// Called when the user signs out or identity should be cleared.
    func reset()
}

// MARK: - AnalyticsTracker

/// Thread-safe, protocol-based analytics tracker that fans events out to
/// one or more `AnalyticsBackend` implementations.
///
/// Usage:
/// ```swift
/// let tracker = AnalyticsTracker.shared
/// tracker.addBackend(FirebaseBackend())
/// tracker.set(globalProperty: "plan", value: "pro")
/// tracker.track(event: PurchaseEvent(sku: "premium_monthly"))
/// ```
public final class AnalyticsTracker: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared tracker used throughout the app. You may also create instances directly.
    public static let shared = AnalyticsTracker()

    // MARK: - Private State

    private let lock = NSLock()
    private var backends: [any AnalyticsBackend] = []
    private var globalProperties: [String: Any] = [:]
    private var userId: String?
    private var sessionId: String
    private var eventCount: Int = 0

    // MARK: - Init

    public init() {
        sessionId = UUID().uuidString
    }

    // MARK: - Backend Management

    /// Registers an analytics backend. Events are forwarded to all registered backends.
    public func addBackend(_ backend: any AnalyticsBackend) {
        lock.withLock { backends.append(backend) }
    }

    /// Removes all registered backends.
    public func removeAllBackends() {
        lock.withLock { backends.removeAll() }
    }

    // MARK: - Global Properties

    /// Sets a property that is merged into every subsequent event.
    /// Pass `nil` to remove the property.
    public func set(globalProperty key: String, value: Any?) {
        lock.withLock {
            if let value {
                globalProperties[key] = value
            } else {
                globalProperties.removeValue(forKey: key)
            }
        }
    }

    /// Replaces all global properties at once.
    public func setGlobalProperties(_ properties: [String: Any]) {
        lock.withLock { globalProperties = properties }
    }

    /// Returns a snapshot of the current global properties.
    public var currentGlobalProperties: [String: Any] {
        lock.withLock { globalProperties }
    }

    // MARK: - Identity

    /// Associates subsequent events with a user identity.
    public func identify(userId: String, traits: [String: Any] = [:]) {
        lock.withLock {
            self.userId = userId
            globalProperties["userId"] = userId
        }
        fanOut { $0.identify(userId: userId, traits: traits) }
    }

    /// Clears the user identity and starts a new session. Call on sign-out.
    public func reset() {
        lock.withLock {
            userId = nil
            globalProperties.removeValue(forKey: "userId")
            sessionId = UUID().uuidString
            eventCount = 0
        }
        fanOut { $0.reset() }
    }

    // MARK: - Tracking

    /// Tracks a structured `AnalyticsEvent`, merging global properties.
    public func track(event: any AnalyticsEvent) {
        let merged = buildMergedProperties(eventProperties: event.properties)
        fanOut { $0.track(event: event, mergedProperties: merged) }
    }

    /// Tracks a freeform event by name with optional extra properties.
    public func track(_ name: String, properties: [String: Any] = [:]) {
        let event = SimpleEvent(name: name, properties: properties)
        track(event: event)
    }

    // MARK: - Session Info

    /// Current session identifier, refreshed on `reset()`.
    public var currentSessionId: String {
        lock.withLock { sessionId }
    }

    /// Total events tracked since init (or last `reset()`).
    public var trackedEventCount: Int {
        lock.withLock { eventCount }
    }

    // MARK: - Private Helpers

    private func buildMergedProperties(eventProperties: [String: Any]) -> [String: Any] {
        lock.withLock {
            eventCount += 1
            var merged = globalProperties
            merged["sessionId"] = sessionId
            merged["eventIndex"] = eventCount
            for (k, v) in eventProperties { merged[k] = v }
            return merged
        }
    }

    private func fanOut(_ action: (any AnalyticsBackend) -> Void) {
        let snapshot = lock.withLock { backends }
        snapshot.forEach(action)
    }
}

// MARK: - Internal Simple Event

private struct SimpleEvent: AnalyticsEvent {
    let name: String
    let properties: [String: Any]
}

// MARK: - NSLock convenience

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
