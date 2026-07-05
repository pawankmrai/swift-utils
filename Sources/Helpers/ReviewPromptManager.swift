import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ReviewPromptCriteria

/// Configurable thresholds that determine when it is appropriate to ask a user
/// to rate the app, so prompts feel earned rather than intrusive.
public struct ReviewPromptCriteria: Sendable, Equatable {
    /// Minimum number of "significant events" (e.g. completed checkouts, saved
    /// projects) the user must record before a prompt is eligible.
    public var minSignificantEvents: Int

    /// Minimum number of days since first launch before a prompt is eligible.
    public var minDaysSinceFirstLaunch: Int

    /// Minimum number of days that must pass between two prompts.
    public var minDaysBetweenPrompts: Int

    /// If `true`, the user is never prompted twice for the same
    /// `CFBundleShortVersionString`, even if all other criteria are met again.
    public var promptOncePerAppVersion: Bool

    public init(
        minSignificantEvents: Int = 5,
        minDaysSinceFirstLaunch: Int = 3,
        minDaysBetweenPrompts: Int = 90,
        promptOncePerAppVersion: Bool = true
    ) {
        self.minSignificantEvents = minSignificantEvents
        self.minDaysSinceFirstLaunch = minDaysSinceFirstLaunch
        self.minDaysBetweenPrompts = minDaysBetweenPrompts
        self.promptOncePerAppVersion = promptOncePerAppVersion
    }

    /// Anthropic-style sensible defaults: 5 significant events, 3 days installed,
    /// at most one prompt every 90 days, never twice per version.
    public static let `default` = ReviewPromptCriteria()
}

// MARK: - ReviewPromptManager

/// Tracks usage signals on-device and decides when it is appropriate to request
/// an App Store review via `SKStoreReviewController`, so you never have to hand-roll
/// the throttling logic yourself.
///
/// All state is persisted in `UserDefaults`. The manager never calls the system
/// review sheet directly unless `isEligible` is `true`, keeping you compliant with
/// Apple's guideline that prompts must not be forced on every launch.
///
/// ```swift
/// // Somewhere the user completes a meaningful action:
/// ReviewPromptManager.shared.recordSignificantEvent()
///
/// // Later, in a safe spot in the UI flow (e.g. after a success screen):
/// if let scene = view.window?.windowScene {
///     ReviewPromptManager.shared.requestReviewIfEligible(in: scene)
/// }
/// ```
public final class ReviewPromptManager {

    // MARK: Public

    /// Shared singleton — suitable for most apps.
    public static let shared = ReviewPromptManager()

    /// The criteria used to decide eligibility. Mutate to tune the throttling.
    public var criteria: ReviewPromptCriteria

    /// The date the manager first recorded activity for this install.
    public var firstLaunchDate: Date {
        if let stored = defaults.object(forKey: Keys.firstLaunchDate) as? Date {
            return stored
        }
        let date = now()
        defaults.set(date, forKey: Keys.firstLaunchDate)
        return date
    }

    /// The number of significant events recorded so far.
    public var significantEventCount: Int {
        defaults.integer(forKey: Keys.eventCount)
    }

    /// The date of the most recent successful prompt, or `nil` if never prompted.
    public var lastPromptDate: Date? {
        defaults.object(forKey: Keys.lastPromptDate) as? Date
    }

    /// The app version (`CFBundleShortVersionString`) that was current at the last prompt.
    public var lastPromptedVersion: String? {
        defaults.string(forKey: Keys.lastPromptedVersion)
    }

    /// The running app's current short version string, or `"unknown"` if unavailable.
    public var currentAppVersion: String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// Whether every configured criterion is currently satisfied. Has no side effects,
    /// so it is safe to call repeatedly (e.g. to decide whether to even show a
    /// "Rate Us" menu item).
    public var isEligible: Bool {
        guard daysBetween(firstLaunchDate, now()) >= criteria.minDaysSinceFirstLaunch else {
            return false
        }
        guard significantEventCount >= criteria.minSignificantEvents else {
            return false
        }
        if let lastPrompt = lastPromptDate,
           daysBetween(lastPrompt, now()) < criteria.minDaysBetweenPrompts {
            return false
        }
        if criteria.promptOncePerAppVersion,
           let lastVersion = lastPromptedVersion,
           lastVersion == currentAppVersion {
            return false
        }
        return true
    }

    // MARK: Init

    /// Creates an independent manager. Inject a custom `UserDefaults` suite, `Bundle`,
    /// or clock for testing.
    ///
    /// - Parameters:
    ///   - criteria: The eligibility thresholds. Defaults to `.default`.
    ///   - userDefaults: Backing store for persisted state. Defaults to `.standard`.
    ///   - bundle: Source of the current app version. Defaults to `.main`.
    ///   - now: Clock used for all date math. Defaults to `Date.init`.
    public init(
        criteria: ReviewPromptCriteria = .default,
        userDefaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init
    ) {
        self.criteria = criteria
        self.defaults = userDefaults
        self.bundle = bundle
        self.now = now
    }

    // MARK: - Recording

    /// Records that the user completed a "significant" action worth counting toward
    /// the eligibility threshold (e.g. finished onboarding, exported a file, hit a streak).
    public func recordSignificantEvent() {
        defaults.set(significantEventCount + 1, forKey: Keys.eventCount)
    }

    /// Clears all persisted state, as if the manager had never run. Useful for
    /// debug menus and unit tests.
    public func reset() {
        defaults.removeObject(forKey: Keys.firstLaunchDate)
        defaults.removeObject(forKey: Keys.eventCount)
        defaults.removeObject(forKey: Keys.lastPromptDate)
        defaults.removeObject(forKey: Keys.lastPromptedVersion)
    }

    // MARK: - Requesting

    #if canImport(StoreKit) && canImport(UIKit)
    /// Requests an App Store review if `isEligible` is `true`, then records the
    /// prompt so future eligibility checks respect the configured throttling.
    ///
    /// - Parameter scene: The active `UIWindowScene` to present the system sheet in.
    /// - Returns: `true` if the review sheet was requested, `false` if criteria weren't met.
    @available(iOS 15.0, *)
    @MainActor
    @discardableResult
    public func requestReviewIfEligible(in scene: UIWindowScene) -> Bool {
        guard isEligible else { return false }
        SKStoreReviewController.requestReview(in: scene)
        markPrompted()
        return true
    }
    #endif

    /// Records that a prompt occurred without presenting anything, for platforms or
    /// tests where `SKStoreReviewController` isn't available.
    public func markPrompted() {
        defaults.set(now(), forKey: Keys.lastPromptDate)
        defaults.set(currentAppVersion, forKey: Keys.lastPromptedVersion)
    }

    // MARK: - Private

    private let defaults: UserDefaults
    private let bundle: Bundle
    private let now: () -> Date

    private enum Keys {
        static let firstLaunchDate = "ReviewPromptManager.firstLaunchDate"
        static let eventCount = "ReviewPromptManager.eventCount"
        static let lastPromptDate = "ReviewPromptManager.lastPromptDate"
        static let lastPromptedVersion = "ReviewPromptManager.lastPromptedVersion"
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
