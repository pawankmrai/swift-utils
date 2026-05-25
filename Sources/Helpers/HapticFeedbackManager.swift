//
//  HapticFeedbackManager.swift
//  SwiftUtils
//
//  A lightweight wrapper around UIKit's haptic feedback generators
//  providing a simple, expressive API for triggering haptics in iOS apps.
//

import UIKit

/// A centralized manager for triggering haptic feedback with a clean, expressive API.
///
/// `HapticFeedbackManager` wraps UIKit's feedback generators and provides:
/// - One-liner haptic triggers for common feedback types
/// - Prepared generators for latency-sensitive interactions
/// - Pattern playback for custom haptic sequences
/// - Automatic availability checking for device support
///
/// Usage:
/// ```swift
/// HapticFeedbackManager.shared.impact(.medium)
/// ```
public final class HapticFeedbackManager: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance for convenient access.
    public static let shared = HapticFeedbackManager()

    // MARK: - Types

    /// Impact feedback styles matching UIKit intensity levels.
    public enum ImpactStyle {
        case light
        case medium
        case heavy
        case soft
        case rigid

        fileprivate var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: return .light
            case .medium: return .medium
            case .heavy: return .heavy
            case .soft: return .soft
            case .rigid: return .rigid
            }
        }
    }

    /// Notification feedback types for status communication.
    public enum NotificationType {
        case success
        case warning
        case error

        fileprivate var uiKitType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            }
        }
    }

    /// A single element in a haptic pattern sequence.
    public enum PatternElement {
        /// An impact haptic with specified style and optional custom intensity (0.0–1.0).
        case impact(ImpactStyle, intensity: CGFloat? = nil)
        /// A notification haptic.
        case notification(NotificationType)
        /// A selection tick.
        case selection
        /// A pause between haptic events (seconds).
        case pause(TimeInterval)
    }

    // MARK: - Properties

    private let selectionGenerator: UISelectionFeedbackGenerator
    private let notificationGenerator: UINotificationFeedbackGenerator
    private var impactGenerators: [ImpactStyle: UIImpactFeedbackGenerator] = [:]
    private let lock = NSLock()

    /// Whether haptic feedback is enabled. Set to `false` to silently suppress all haptics.
    public var isEnabled: Bool = true

    // MARK: - Initialization

    /// Creates a new haptic feedback manager.
    public init() {
        self.selectionGenerator = UISelectionFeedbackGenerator()
        self.notificationGenerator = UINotificationFeedbackGenerator()
    }

    // MARK: - Device Support

    /// Whether the current device supports haptic feedback.
    ///
    /// Returns `true` on iPhone 7 and later. Older devices and iPad silently no-op.
    public var supportsHaptics: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    // MARK: - Basic Triggers

    /// Triggers an impact haptic with the given style.
    ///
    /// - Parameter style: The intensity style of the impact (default: `.medium`).
    public func impact(_ style: ImpactStyle = .medium) {
        guard isEnabled else { return }
        generator(for: style).impactOccurred()
    }

    /// Triggers an impact haptic with a custom intensity.
    ///
    /// - Parameters:
    ///   - style: The base style of the impact.
    ///   - intensity: A value between 0.0 and 1.0 controlling the strength.
    public func impact(_ style: ImpactStyle = .medium, intensity: CGFloat) {
        guard isEnabled else { return }
        let clamped = min(max(intensity, 0.0), 1.0)
        generator(for: style).impactOccurred(intensity: clamped)
    }

    /// Triggers a notification haptic (success, warning, or error).
    ///
    /// - Parameter type: The notification type to communicate.
    public func notification(_ type: NotificationType) {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(type.uiKitType)
    }

    /// Triggers a subtle selection tick, ideal for picker changes or toggle switches.
    public func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    // MARK: - Preparation

    /// Prepares generators for immediate use, reducing latency on first trigger.
    ///
    /// Call this when you anticipate haptic feedback will be needed shortly,
    /// such as on `touchDown` or when a draggable view is grabbed.
    public func prepare() {
        selectionGenerator.prepare()
        notificationGenerator.prepare()
        lock.lock()
        impactGenerators.values.forEach { $0.prepare() }
        lock.unlock()
    }

    /// Prepares a specific impact generator for immediate use.
    ///
    /// - Parameter style: The impact style to prepare.
    public func prepare(_ style: ImpactStyle) {
        generator(for: style).prepare()
    }

    // MARK: - Pattern Playback

    /// Plays a sequence of haptic elements with timing control.
    ///
    /// Use patterns to create expressive feedback sequences like a "heartbeat"
    /// or escalating alerts.
    ///
    /// - Parameter elements: An array of `PatternElement` values to play in order.
    public func playPattern(_ elements: [PatternElement]) async {
        guard isEnabled else { return }
        for element in elements {
            switch element {
            case .impact(let style, let intensity):
                if let intensity {
                    self.impact(style, intensity: intensity)
                } else {
                    self.impact(style)
                }
            case .notification(let type):
                self.notification(type)
            case .selection:
                self.selection()
            case .pause(let duration):
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
        }
    }

    // MARK: - Convenience Patterns

    /// A double-tap impact pattern, useful for confirming actions.
    public func doubleTap(style: ImpactStyle = .medium) async {
        await playPattern([
            .impact(style),
            .pause(0.1),
            .impact(style)
        ])
    }

    /// An escalating alert pattern: light → medium → heavy.
    public func escalate() async {
        await playPattern([
            .impact(.light),
            .pause(0.08),
            .impact(.medium),
            .pause(0.08),
            .impact(.heavy)
        ])
    }

    /// A heartbeat pattern with two quick pulses.
    public func heartbeat() async {
        await playPattern([
            .impact(.heavy, intensity: 0.8),
            .pause(0.12),
            .impact(.light, intensity: 0.4),
            .pause(0.4),
            .impact(.heavy, intensity: 0.8),
            .pause(0.12),
            .impact(.light, intensity: 0.4)
        ])
    }

    // MARK: - Private Helpers

    private func generator(for style: ImpactStyle) -> UIImpactFeedbackGenerator {
        lock.lock()
        defer { lock.unlock() }
        if let existing = impactGenerators[style] {
            return existing
        }
        let gen = UIImpactFeedbackGenerator(style: style.uiKitStyle)
        impactGenerators[style] = gen
        return gen
    }
}
