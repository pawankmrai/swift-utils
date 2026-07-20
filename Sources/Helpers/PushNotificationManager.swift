import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

// MARK: - PushNotificationPayload

/// A parsed, type-safe view over the raw `userInfo` dictionary delivered with a
/// remote (push) notification.
///
/// Reads the standard Apple Push Notification `aps` fields (`alert`, `category`,
/// `thread-id`, `badge`, `sound`) and captures every other top-level key as
/// `customData` for your own application payload.
public struct PushNotificationPayload: Sendable, Equatable {
    /// The alert title, if the payload used the dictionary form of `alert`.
    public let title: String?

    /// The alert body. Populated whether `alert` was a plain string or a dictionary.
    public let body: String?

    /// The `aps.category` identifier, used to route the payload to a registered handler.
    public let category: String?

    /// The `aps.thread-id`, useful for grouping notifications in the Notification Center.
    public let threadIdentifier: String?

    /// The `aps.badge` value, if present.
    public let badge: Int?

    /// The `aps.sound` name, if present.
    public let sound: String?

    /// Every non-`aps` top-level key from the payload, stringified for convenience.
    public let customData: [String: String]

    /// Parses a payload from the `userInfo` dictionary handed to you by
    /// `UNUserNotificationCenterDelegate` or `application(_:didReceiveRemoteNotification:)`.
    public init(userInfo: [AnyHashable: Any]) {
        let aps = userInfo["aps"] as? [String: Any] ?? [:]

        if let alertDict = aps["alert"] as? [String: Any] {
            title = alertDict["title"] as? String
            body = alertDict["body"] as? String
        } else {
            title = nil
            body = aps["alert"] as? String
        }

        category = aps["category"] as? String
        threadIdentifier = aps["thread-id"] as? String
        badge = (aps["badge"] as? NSNumber)?.intValue
        sound = aps["sound"] as? String

        var custom: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String, key != "aps" else { continue }
            custom[key] = "\(value)"
        }
        customData = custom
    }
}

// MARK: - PushNotificationManager

/// Coordinates remote push notification registration, device token handling, and
/// payload routing, so `AppDelegate`/`SceneDelegate` boilerplate stays out of your
/// feature code.
///
/// This complements ``NotificationScheduler`` (which schedules *local* notifications)
/// by covering the remote-notification lifecycle: requesting authorization,
/// registering with APNs, capturing the device token, and dispatching incoming
/// payloads to per-category handlers.
///
/// ```swift
/// // In AppDelegate:
/// func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
///     PushNotificationManager.shared.onNotification(category: "CHAT_MESSAGE") { payload in
///         openConversation(id: payload.customData["conversationId"])
///     }
///     Task { try? await PushNotificationManager.shared.requestAuthorization() }
///     return true
/// }
///
/// func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
///     let token = PushNotificationManager.shared.handleDeviceToken(deviceToken)
///     uploadTokenToServer(token)
/// }
/// ```
public final class PushNotificationManager: NSObject, @unchecked Sendable {

    // MARK: Singleton

    /// Shared instance suitable for most apps.
    public static let shared = PushNotificationManager()

    // MARK: State

    /// The current APNs device token as a lowercase hex string, or `nil` if not yet registered.
    public private(set) var deviceToken: String?

    /// The raw `Data` device token most recently reported by the system.
    public private(set) var deviceTokenData: Data?

    /// The most recent registration error, if `handleRegistrationFailure` was called.
    public private(set) var registrationError: Error?

    // MARK: Init

    public override init() {
        super.init()
    }

    // MARK: - Authorization & Registration

    #if canImport(UserNotifications)
    /// Requests permission to display alerts, badges, and play sounds for remote notifications.
    ///
    /// - Parameter options: The authorization options to request. Defaults to alert, badge, and sound.
    /// - Returns: `true` if the user granted authorization.
    @discardableResult
    public func requestAuthorization(
        options: UNAuthorizationOptions = [.alert, .badge, .sound]
    ) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    /// The current system authorization status for notifications.
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    #endif

    #if canImport(UIKit) && !os(watchOS) && !os(macOS)
    /// Triggers APNs registration. Call after authorization is granted; the resulting
    /// token or error arrives via your `AppDelegate` callbacks, which you should forward
    /// to ``handleDeviceToken(_:)`` / ``handleRegistrationFailure(_:)``.
    @MainActor
    public func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    #endif

    // MARK: - Token handling

    /// Converts the raw device token `Data` to a hex string, stores it, and notifies
    /// any active ``tokenUpdates()`` subscribers.
    ///
    /// - Parameter tokenData: The `Data` passed to
    ///   `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// - Returns: The hex-encoded token, ready to send to your push server.
    @discardableResult
    public func handleDeviceToken(_ tokenData: Data) -> String {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceTokenData = tokenData
        deviceToken = hex
        registrationError = nil
        broadcast(hex)
        return hex
    }

    /// Records a failure to register for remote notifications, clearing any stored token.
    ///
    /// - Parameter error: The error passed to
    ///   `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    public func handleRegistrationFailure(_ error: Error) {
        registrationError = error
        deviceToken = nil
        deviceTokenData = nil
    }

    /// An `AsyncStream` that yields the current token immediately (if any) and every
    /// subsequent token produced by ``handleDeviceToken(_:)``, e.g. after re-registration.
    public func tokenUpdates() -> AsyncStream<String> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            tokenContinuations[id] = continuation
            let existing = deviceToken
            lock.unlock()

            if let existing {
                continuation.yield(existing)
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    // MARK: - Payload routing

    /// Registers a handler invoked whenever an incoming payload's `aps.category`
    /// matches `category`. Replaces any previously registered handler for that category.
    public func onNotification(category: String, handler: @escaping (PushNotificationPayload) -> Void) {
        lock.lock()
        categoryHandlers[category] = handler
        lock.unlock()
    }

    /// Registers a fallback handler invoked for payloads with no category, or whose
    /// category has no registered handler.
    public func onUnhandledNotification(_ handler: @escaping (PushNotificationPayload) -> Void) {
        lock.lock()
        defaultHandler = handler
        lock.unlock()
    }

    /// Parses `userInfo` and dispatches it to the matching category handler (or the
    /// default handler). Call this from
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)` or
    /// `application(_:didReceiveRemoteNotification:)`.
    ///
    /// - Returns: `true` if a handler was found and invoked.
    @discardableResult
    public func handle(userInfo: [AnyHashable: Any]) -> Bool {
        let payload = PushNotificationPayload(userInfo: userInfo)

        lock.lock()
        let handler = payload.category.flatMap { categoryHandlers[$0] } ?? defaultHandler
        lock.unlock()

        guard let handler else { return false }
        handler(payload)
        return true
    }

    /// Removes all registered category and default handlers. Useful for tests and
    /// for tearing down state on sign-out.
    public func removeAllHandlers() {
        lock.lock()
        categoryHandlers.removeAll()
        defaultHandler = nil
        lock.unlock()
    }

    /// Clears the stored device token, error, and all pending token-update subscribers.
    /// Call on sign-out so a stale token isn't reused for the next signed-in user.
    public func reset() {
        deviceToken = nil
        deviceTokenData = nil
        registrationError = nil
        lock.lock()
        tokenContinuations.removeAll()
        lock.unlock()
    }

    // MARK: - Private

    private let lock = NSLock()
    private var categoryHandlers: [String: (PushNotificationPayload) -> Void] = [:]
    private var defaultHandler: ((PushNotificationPayload) -> Void)?
    private var tokenContinuations: [UUID: AsyncStream<String>.Continuation] = [:]

    private func broadcast(_ token: String) {
        lock.lock()
        let continuations = Array(tokenContinuations.values)
        lock.unlock()
        for continuation in continuations {
            continuation.yield(token)
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        tokenContinuations.removeValue(forKey: id)
        lock.unlock()
    }
}
