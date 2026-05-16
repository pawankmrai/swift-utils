//
//  FeatureFlagManager.swift
//  swift-utils
//
//  A lightweight, type-safe feature flag manager for iOS applications.
//  Supports local defaults, remote overrides, and observation of flag changes.
//
//  Created by Pawan on 2026-05-16.
//

import Foundation

// MARK: - Feature Flag Definition

/// A type-safe feature flag definition that associates a key with a default value.
///
/// Usage:
/// ```swift
/// extension FeatureFlag {
///     static let darkMode = FeatureFlag<Bool>(key: "dark_mode", defaultValue: false)
///     static let maxRetries = FeatureFlag<Int>(key: "max_retries", defaultValue: 3)
///     static let welcomeMessage = FeatureFlag<String>(key: "welcome_msg", defaultValue: "Hello!")
/// }
/// ```
public struct FeatureFlag<Value: Codable & Equatable>: Hashable {
    /// The unique key identifying this flag.
    public let key: String
    
    /// The default value returned when no override is set.
    public let defaultValue: Value
    
    public init(key: String, defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
    
    public static func == (lhs: FeatureFlag, rhs: FeatureFlag) -> Bool {
        lhs.key == rhs.key
    }
}

// MARK: - Flag Change Notification

/// Describes a change in a feature flag's value.
public struct FlagChange<Value> {
    public let key: String
    public let oldValue: Value
    public let newValue: Value
}

// MARK: - Feature Flag Provider Protocol

/// A source of feature flag values. Implement this to integrate with
/// remote config services (Firebase, LaunchDarkly, etc.).
public protocol FeatureFlagProvider {
    /// Returns the value for the given key, or nil if the provider has no value.
    func value<Value: Codable>(forKey key: String, type: Value.Type) -> Value?
}

// MARK: - Feature Flag Manager

/// A centralized manager for feature flags that supports layered value resolution,
/// local overrides, and change observation.
///
/// Value resolution order (first non-nil wins):
/// 1. Local overrides (set via `setOverride`)
/// 2. Registered providers (checked in registration order)
/// 3. Flag's default value
///
/// Example:
/// ```swift
/// let manager = FeatureFlagManager.shared
///
/// // Define flags
/// extension FeatureFlag {
///     static let newOnboarding = FeatureFlag<Bool>(key: "new_onboarding", defaultValue: false)
/// }
///
/// // Read a flag
/// if manager.value(for: .newOnboarding) {
///     showNewOnboarding()
/// }
///
/// // Set a local override (useful for testing or debug menus)
/// manager.setOverride(true, for: .newOnboarding)
///
/// // Observe changes
/// let token = manager.observe(.newOnboarding) { change in
///     print("Onboarding flag changed: \(change.oldValue) → \(change.newValue)")
/// }
/// ```
public final class FeatureFlagManager: @unchecked Sendable {
    
    /// Shared singleton instance.
    public static let shared = FeatureFlagManager()
    
    private let queue = DispatchQueue(label: "com.swiftutils.featureflags", attributes: .concurrent)
    private var providers: [FeatureFlagProvider] = []
    private var overrides: [String: Data] = [:]
    private var observers: [String: [(id: UUID, callback: Any)]] = [:]
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init() {}
    
    // MARK: - Provider Management
    
    /// Registers a feature flag provider. Providers are queried in registration order.
    ///
    /// - Parameter provider: The provider to register.
    public func registerProvider(_ provider: FeatureFlagProvider) {
        queue.async(flags: .barrier) {
            self.providers.append(provider)
        }
    }
    
    /// Removes all registered providers.
    public func removeAllProviders() {
        queue.async(flags: .barrier) {
            self.providers.removeAll()
        }
    }
    
    // MARK: - Value Resolution
    
    /// Returns the current value for the given feature flag.
    ///
    /// Resolution order: local override → providers → default value.
    ///
    /// - Parameter flag: The feature flag to query.
    /// - Returns: The resolved value.
    public func value<Value: Codable & Equatable>(for flag: FeatureFlag<Value>) -> Value {
        queue.sync {
            // 1. Check local overrides
            if let data = overrides[flag.key],
               let decoded = try? decoder.decode(Value.self, from: data) {
                return decoded
            }
            
            // 2. Check providers in order
            for provider in providers {
                if let val = provider.value(forKey: flag.key, type: Value.self) {
                    return val
                }
            }
            
            // 3. Return default
            return flag.defaultValue
        }
    }
    
    /// Returns whether a boolean feature flag is enabled.
    ///
    /// Convenience method for `Bool` flags.
    ///
    /// - Parameter flag: A boolean feature flag.
    /// - Returns: `true` if the flag is enabled.
    public func isEnabled(_ flag: FeatureFlag<Bool>) -> Bool {
        value(for: flag)
    }
    
    // MARK: - Local Overrides
    
    /// Sets a local override for a feature flag.
    ///
    /// Overrides take highest priority in value resolution and persist
    /// for the lifetime of the manager (or until cleared).
    ///
    /// - Parameters:
    ///   - newValue: The override value.
    ///   - flag: The feature flag to override.
    public func setOverride<Value: Codable & Equatable>(_ newValue: Value, for flag: FeatureFlag<Value>) {
        let oldValue = value(for: flag)
        
        queue.async(flags: .barrier) {
            if let data = try? self.encoder.encode(newValue) {
                self.overrides[flag.key] = data
            }
        }
        
        if oldValue != newValue {
            notifyObservers(for: flag, oldValue: oldValue, newValue: newValue)
        }
    }
    
    /// Removes the local override for a feature flag, reverting to
    /// provider values or the default.
    ///
    /// - Parameter flag: The feature flag whose override should be removed.
    public func removeOverride<Value: Codable & Equatable>(for flag: FeatureFlag<Value>) {
        let oldValue = value(for: flag)
        
        queue.async(flags: .barrier) {
            self.overrides.removeValue(forKey: flag.key)
        }
        
        let newValue = value(for: flag)
        if oldValue != newValue {
            notifyObservers(for: flag, oldValue: oldValue, newValue: newValue)
        }
    }
    
    /// Removes all local overrides.
    public func removeAllOverrides() {
        queue.async(flags: .barrier) {
            self.overrides.removeAll()
        }
    }
    
    /// Returns `true` if a local override exists for the given flag.
    public func hasOverride<Value: Codable & Equatable>(for flag: FeatureFlag<Value>) -> Bool {
        queue.sync {
            overrides[flag.key] != nil
        }
    }
    
    // MARK: - Observation
    
    /// Observes changes to a feature flag's value.
    ///
    /// The callback fires whenever the resolved value changes due to
    /// `setOverride` or `removeOverride`.
    ///
    /// - Parameters:
    ///   - flag: The feature flag to observe.
    ///   - callback: A closure called with the change details.
    /// - Returns: An `ObservationToken` that cancels observation when deallocated.
    @discardableResult
    public func observe<Value: Codable & Equatable>(
        _ flag: FeatureFlag<Value>,
        callback: @escaping (FlagChange<Value>) -> Void
    ) -> ObservationToken {
        let id = UUID()
        
        queue.async(flags: .barrier) {
            var list = self.observers[flag.key] ?? []
            list.append((id: id, callback: callback))
            self.observers[flag.key] = list
        }
        
        return ObservationToken { [weak self] in
            self?.removeObserver(id: id, forKey: flag.key)
        }
    }
    
    private func removeObserver(id: UUID, forKey key: String) {
        queue.async(flags: .barrier) {
            self.observers[key]?.removeAll { $0.id == id }
        }
    }
    
    private func notifyObservers<Value: Codable & Equatable>(
        for flag: FeatureFlag<Value>,
        oldValue: Value,
        newValue: Value
    ) {
        let change = FlagChange(key: flag.key, oldValue: oldValue, newValue: newValue)
        
        queue.sync {
            guard let list = observers[flag.key] else { return }
            for entry in list {
                if let cb = entry.callback as? (FlagChange<Value>) -> Void {
                    cb(change)
                }
            }
        }
    }
    
    // MARK: - Bulk Operations
    
    /// Returns a snapshot of all current overrides as a dictionary of key → JSON data.
    /// Useful for debugging or persisting overrides.
    public func allOverrides() -> [String: Data] {
        queue.sync { overrides }
    }
    
    /// Resets the manager to its initial state: removes overrides, providers, and observers.
    public func reset() {
        queue.async(flags: .barrier) {
            self.overrides.removeAll()
            self.providers.removeAll()
            self.observers.removeAll()
        }
    }
}

// MARK: - Observation Token

/// A token returned by `observe(_:callback:)` that cancels the observation
/// when deallocated or when `cancel()` is called.
public final class ObservationToken {
    private var cancellation: (() -> Void)?
    
    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }
    
    /// Cancels the observation.
    public func cancel() {
        cancellation?()
        cancellation = nil
    }
    
    deinit {
        cancel()
    }
}

// MARK: - Dictionary Provider

/// A simple provider backed by a `[String: Any]` dictionary.
/// Useful for testing or loading flags from a JSON config file.
///
/// Example:
/// ```swift
/// let provider = DictionaryFlagProvider(values: [
///     "dark_mode": true,
///     "max_retries": 5
/// ])
/// manager.registerProvider(provider)
/// ```
public final class DictionaryFlagProvider: FeatureFlagProvider {
    private let values: [String: Any]
    
    public init(values: [String: Any]) {
        self.values = values
    }
    
    public func value<Value: Codable>(forKey key: String, type: Value.Type) -> Value? {
        values[key] as? Value
    }
}
