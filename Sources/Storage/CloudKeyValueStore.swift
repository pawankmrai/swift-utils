import Foundation

/// A minimal interface over key-value cloud storage, satisfied by `NSUbiquitousKeyValueStore`.
///
/// Abstracting the store behind a protocol keeps `CloudKeyValueStore` and `@CloudStorage`
/// unit-testable without iCloud entitlements — tests can inject an in-memory fake instead
/// of touching the real ubiquitous store.
public protocol CloudKeyValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
    var dictionaryRepresentation: [String: Any] { get }
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStoring {}

/// A protocol that types must conform to in order to be stored via `@CloudStorage`.
///
/// Built-in conformances are provided for `Bool`, `Int`, `Double`, `Float`, `String`,
/// and `Data`. `NSUbiquitousKeyValueStore` only supports property-list-compatible
/// values, so richer types should go through `@CloudCodableStorage` instead.
public protocol CloudValueStorable {
    static func read(from store: CloudKeyValueStoring, forKey key: String) -> Self?
    static func write(_ value: Self, to store: CloudKeyValueStoring, forKey key: String)
}

extension Bool: CloudValueStorable {
    public static func read(from store: CloudKeyValueStoring, forKey key: String) -> Bool? {
        (store.object(forKey: key) as? NSNumber)?.boolValue
    }
    public static func write(_ value: Bool, to store: CloudKeyValueStoring, forKey key: String) {
        store.set(value, forKey: key)
    }
}

extension Int: CloudValueStorable {
    public static func read(from store: CloudKeyValueStoring, forKey key: String) -> Int? {
        (store.object(forKey: key) as? NSNumber)?.intValue
    }
    public static func write(_ value: Int, to store: CloudKeyValueStoring, forKey key: String) {
        store.set(value, forKey: key)
    }
}

extension Double: CloudValueStorable {
    public static func read(from store: CloudKeyValueStoring, forKey key: String) -> Double? {
        (store.object(forKey: key) as? NSNumber)?.doubleValue
    }
    public static func write(_ value: Double, to store: CloudKeyValueStoring, forKey key: String) {
        store.set(value, forKey: key)
    }
}

extension Float: CloudValueStorable {
    public static func read(from store: CloudKeyValueStoring, forKey key: String) -> Float? {
        (store.object(forKey: key) as? NSNumber)?.floatValue
    }
    public static func write(_ value: Float, to store: CloudKeyValueStoring, forKey key: String) {
        store.set(value, forKey: key)
    }
}

extension String: CloudValueStorable {
    public static func read(from store: CloudKeyValueStoring, forKey key: String) -> String? {
        store.object(forKey: key) as? String
    }
    public static func write(_ value: String, to store: CloudKeyValueStoring, forKey key: String) {
        store.set(value, forKey: key)
    }
}

extension Data: CloudValueStorable {
    public static func read(from store: CloudKeyValueStoring, forKey key: String) -> Data? {
        store.object(forKey: key) as? Data
    }
    public static func write(_ value: Data, to store: CloudKeyValueStoring, forKey key: String) {
        store.set(value, forKey: key)
    }
}

/// A property wrapper that syncs a value to `NSUbiquitousKeyValueStore` (iCloud key-value
/// storage), giving small pieces of app state — preferences, a "did see onboarding" flag,
/// a last-read article ID — a free ride across a user's devices.
///
/// iCloud key-value storage is capped at 1 MB total and 1024 keys, so it's meant for
/// lightweight settings, not documents or large blobs.
///
/// Usage:
/// ```swift
/// struct Preferences {
///     @CloudStorage("preferred_units", defaultValue: "metric")
///     static var preferredUnits: String
///
///     @CloudStorage("has_seen_tip_jar", defaultValue: false)
///     static var hasSeenTipJar: Bool
/// }
/// ```
@propertyWrapper
public struct CloudStorage<Value: CloudValueStorable> {

    /// The key used to store the value in the cloud store.
    public let key: String

    /// The default value returned when no value exists for the key, or iCloud is unavailable.
    public let defaultValue: Value

    /// The underlying store, defaulting to `NSUbiquitousKeyValueStore.default`.
    public let store: CloudKeyValueStoring

    public init(_ key: String, defaultValue: Value, store: CloudKeyValueStoring = NSUbiquitousKeyValueStore.default) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    public var wrappedValue: Value {
        get { Value.read(from: store, forKey: key) ?? defaultValue }
        set {
            Value.write(newValue, to: store, forKey: key)
            store.synchronize()
        }
    }

    public var projectedValue: CloudStorage<Value> { self }

    /// Removes the stored value, reverting reads to the default.
    public func remove() {
        store.removeObject(forKey: key)
        store.synchronize()
    }

    /// Returns `true` if a value is explicitly stored for this key.
    public var isSet: Bool {
        store.object(forKey: key) != nil
    }
}

/// A `@CloudStorage` variant for arbitrary `Codable` values, stored as JSON `Data`.
///
/// Usage:
/// ```swift
/// struct DisplaySettings: Codable {
///     var theme: String
///     var fontScale: Double
/// }
///
/// struct Preferences {
///     @CloudCodableStorage("display_settings", defaultValue: DisplaySettings(theme: "system", fontScale: 1.0))
///     static var display: DisplaySettings
/// }
/// ```
@propertyWrapper
public struct CloudCodableStorage<Value: Codable> {

    public let key: String
    public let defaultValue: Value
    public let store: CloudKeyValueStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(_ key: String, defaultValue: Value, store: CloudKeyValueStoring = NSUbiquitousKeyValueStore.default) {
        self.key = key
        self.defaultValue = defaultValue
        self.store = store
    }

    public var wrappedValue: Value {
        get {
            guard let data = store.object(forKey: key) as? Data,
                  let value = try? decoder.decode(Value.self, from: data) else {
                return defaultValue
            }
            return value
        }
        set {
            guard let data = try? encoder.encode(newValue) else { return }
            store.set(data, forKey: key)
            store.synchronize()
        }
    }

    public func remove() {
        store.removeObject(forKey: key)
        store.synchronize()
    }
}

/// Observes external changes to `NSUbiquitousKeyValueStore` — updates that arrived from
/// iCloud rather than from this device — and forwards them as a lightweight callback or
/// an `AsyncStream`.
///
/// Register one observer per store early in app launch (after calling `synchronize()`
/// once) so UI bound to `@CloudStorage` properties can refresh when a value changes on
/// another device.
///
/// Usage:
/// ```swift
/// let observer = CloudKeyValueObserver()
/// observer.onChange = { reason, keys in
///     print("iCloud values changed (\(reason)): \(keys)")
///     NotificationCenter.default.post(name: .preferencesDidSync, object: nil)
/// }
/// observer.start()
/// ```
public final class CloudKeyValueObserver {

    /// Why the external change notification fired, mirrored from Apple's documented reasons.
    public enum ChangeReason: Equatable {
        case serverChange
        case initialSyncChange
        case quotaViolationChange
        case accountChange
        case unknown

        init(rawValue: Int?) {
            switch rawValue {
            case NSUbiquitousKeyValueStoreServerChange: self = .serverChange
            case NSUbiquitousKeyValueStoreInitialSyncChange: self = .initialSyncChange
            case NSUbiquitousKeyValueStoreQuotaViolationChange: self = .quotaViolationChange
            case NSUbiquitousKeyValueStoreAccountChange: self = .accountChange
            default: self = .unknown
            }
        }
    }

    /// Called on the main thread whenever the store reports an external change.
    public var onChange: ((ChangeReason, [String]) -> Void)?

    private let store: NSUbiquitousKeyValueStore
    private var token: NSObjectProtocol?
    private var continuation: AsyncStream<(ChangeReason, [String])>.Continuation?

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    /// An `AsyncStream` of `(reason, changedKeys)` tuples, useful in Swift Concurrency
    /// contexts as an alternative to `onChange`.
    public lazy var changes: AsyncStream<(ChangeReason, [String])> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    /// Begins observing `didChangeExternallyNotification` and triggers an initial sync.
    public func start() {
        guard token == nil else { return }
        store.synchronize()
        token = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let reasonRaw = (userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue
            let reason = ChangeReason(rawValue: reasonRaw)
            let keys = userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            self.onChange?(reason, keys)
            self.continuation?.yield((reason, keys))
        }
    }

    /// Stops observing changes.
    public func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
        continuation?.finish()
    }

    /// Whether the current device is signed into iCloud and ubiquitous storage is available.
    public static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    deinit {
        stop()
    }
}
