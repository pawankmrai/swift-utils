import Foundation

/// A property wrapper that provides type-safe access to `UserDefaults` with support
/// for default values, custom keys, and optional types.
///
/// Usage:
/// ```swift
/// struct AppSettings {
///     @UserDefault("has_completed_onboarding", defaultValue: false)
///     static var hasCompletedOnboarding: Bool
///
///     @UserDefault("username")
///     static var username: String?
///
///     @UserDefault("launch_count", defaultValue: 0)
///     static var launchCount: Int
///
///     @UserDefault("selected_theme", defaultValue: .light, suite: .init(suiteName: "group.myapp")!)
///     static var selectedTheme: Theme
/// }
/// ```
@propertyWrapper
public struct UserDefault<Value: UserDefaultsStorable> {

    /// The key used to store the value in UserDefaults
    public let key: String

    /// The default value returned when no value exists for the key
    public let defaultValue: Value

    /// The UserDefaults suite to use
    public let suite: UserDefaults

    /// Creates a property wrapper for a non-optional UserDefaults value.
    /// - Parameters:
    ///   - key: The UserDefaults key
    ///   - defaultValue: The value to return if no stored value exists
    ///   - suite: The UserDefaults suite (defaults to `.standard`)
    public init(_ key: String, defaultValue: Value, suite: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.suite = suite
    }

    public var wrappedValue: Value {
        get { Value.read(from: suite, forKey: key) ?? defaultValue }
        set { Value.write(newValue, to: suite, forKey: key) }
    }

    /// Provides a `Binding`-friendly projected value that includes the key and suite.
    public var projectedValue: UserDefault<Value> { self }

    /// Removes the stored value, reverting to the default.
    public func remove() {
        suite.removeObject(forKey: key)
    }

    /// Returns `true` if a value is explicitly stored for this key.
    public var isSet: Bool {
        suite.object(forKey: key) != nil
    }
}

// MARK: - Optional Support

/// A property wrapper variant for optional UserDefaults values (no default needed).
///
/// Usage:
/// ```swift
/// @OptionalUserDefault("last_sync_date")
/// static var lastSyncDate: Date?
/// ```
@propertyWrapper
public struct OptionalUserDefault<Value: UserDefaultsStorable> {

    public let key: String
    public let suite: UserDefaults

    public init(_ key: String, suite: UserDefaults = .standard) {
        self.key = key
        self.suite = suite
    }

    public var wrappedValue: Value? {
        get { Value.read(from: suite, forKey: key) }
        set {
            if let newValue {
                Value.write(newValue, to: suite, forKey: key)
            } else {
                suite.removeObject(forKey: key)
            }
        }
    }

    public var projectedValue: OptionalUserDefault<Value> { self }

    public func remove() {
        suite.removeObject(forKey: key)
    }

    public var isSet: Bool {
        suite.object(forKey: key) != nil
    }
}

// MARK: - UserDefaultsStorable Protocol

/// A protocol that types must conform to in order to be stored via `@UserDefault`.
///
/// Built-in conformances are provided for: `Bool`, `Int`, `Double`, `Float`, `String`,
/// `Data`, `Date`, `URL`, `Array`, `Dictionary`, and any `RawRepresentable` with a
/// `RawValue` that is itself `UserDefaultsStorable`.
public protocol UserDefaultsStorable {
    /// Reads a value from UserDefaults for the given key.
    static func read(from defaults: UserDefaults, forKey key: String) -> Self?
    /// Writes a value to UserDefaults for the given key.
    static func write(_ value: Self, to defaults: UserDefaults, forKey key: String)
}

// MARK: - Primitive Conformances

extension Bool: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Bool? {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : nil
    }
    public static func write(_ value: Bool, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Int: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Int? {
        defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : nil
    }
    public static func write(_ value: Int, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Double: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Double? {
        defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : nil
    }
    public static func write(_ value: Double, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Float: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Float? {
        defaults.object(forKey: key) != nil ? defaults.float(forKey: key) : nil
    }
    public static func write(_ value: Float, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension String: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> String? {
        defaults.string(forKey: key)
    }
    public static func write(_ value: String, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Data: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }
    public static func write(_ value: Data, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Date: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Date? {
        defaults.object(forKey: key) as? Date
    }
    public static func write(_ value: Date, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension URL: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> URL? {
        defaults.url(forKey: key)
    }
    public static func write(_ value: URL, to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Array: UserDefaultsStorable where Element: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> [Element]? {
        defaults.array(forKey: key) as? [Element]
    }
    public static func write(_ value: [Element], to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Dictionary: UserDefaultsStorable where Key == String, Value: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> [String: Value]? {
        defaults.dictionary(forKey: key) as? [String: Value]
    }
    public static func write(_ value: [String: Value], to defaults: UserDefaults, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

// MARK: - RawRepresentable Support

/// Adds `UserDefaultsStorable` conformance to any `RawRepresentable` whose raw value
/// is itself storable — perfect for enums backed by `String` or `Int`.
///
/// ```swift
/// enum Theme: String, UserDefaultsStorable {
///     case light, dark, system
/// }
/// ```
extension RawRepresentable where Self: UserDefaultsStorable, RawValue: UserDefaultsStorable {
    public static func read(from defaults: UserDefaults, forKey key: String) -> Self? {
        guard let raw = RawValue.read(from: defaults, forKey: key) else { return nil }
        return Self(rawValue: raw)
    }
    public static func write(_ value: Self, to defaults: UserDefaults, forKey key: String) {
        RawValue.write(value.rawValue, to: defaults, forKey: key)
    }
}

// MARK: - Codable Support

/// A wrapper that lets any `Codable` type be stored in UserDefaults via JSON encoding.
///
/// Usage:
/// ```swift
/// @CodableUserDefault("user_profile", defaultValue: UserProfile.empty)
/// static var userProfile: UserProfile
/// ```
@propertyWrapper
public struct CodableUserDefault<Value: Codable> {

    public let key: String
    public let defaultValue: Value
    public let suite: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(_ key: String, defaultValue: Value, suite: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.suite = suite
    }

    public var wrappedValue: Value {
        get {
            guard let data = suite.data(forKey: key),
                  let value = try? decoder.decode(Value.self, from: data) else {
                return defaultValue
            }
            return value
        }
        set {
            guard let data = try? encoder.encode(newValue) else { return }
            suite.set(data, forKey: key)
        }
    }

    public func remove() {
        suite.removeObject(forKey: key)
    }
}
