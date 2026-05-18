//
//  NotificationScheduler.swift
//  SwiftUtils
//
//  A fluent wrapper around UNUserNotificationCenter for scheduling,
//  managing, and querying local notifications.
//

import Foundation
import UserNotifications

// MARK: - NotificationScheduler

/// A convenience layer over `UNUserNotificationCenter` that provides
/// a builder-style API for creating local notifications and simple
/// methods for listing, cancelling, and requesting authorization.
///
/// ```swift
/// try await NotificationScheduler.shared
///     .schedule("reminder-1")
///     .title("Stand up!")
///     .body("Time to stretch your legs.")
///     .after(seconds: 3600)
///     .commit()
/// ```
public final class NotificationScheduler: @unchecked Sendable {

    // MARK: Singleton

    /// Shared instance backed by `UNUserNotificationCenter.current()`.
    public static let shared = NotificationScheduler()

    private let center: UNUserNotificationCenter

    /// Creates a scheduler wrapping the given notification center.
    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: Authorization

    /// Requests notification authorization for the given options.
    /// - Returns: `true` if the user granted permission.
    @discardableResult
    public func requestAuthorization(
        options: UNAuthorizationOptions = [.alert, .sound, .badge]
    ) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    /// Returns the current authorization status without prompting.
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Builder entry point

    /// Begins building a notification with the given identifier.
    ///
    /// - Parameter identifier: A unique string. If a pending notification
    ///   with the same identifier exists it will be replaced on `commit()`.
    /// - Returns: A `NotificationBuilder` you can configure with a fluent API.
    public func schedule(_ identifier: String) -> NotificationBuilder {
        NotificationBuilder(identifier: identifier, center: center)
    }

    // MARK: Querying

    /// Returns identifiers of all pending (not yet delivered) notifications.
    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    /// Returns identifiers of all delivered (visible in Notification Center) notifications.
    public func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    // MARK: Cancellation

    /// Removes pending notifications matching the given identifiers.
    public func cancelPending(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Removes pending notifications matching the given identifiers (variadic).
    public func cancelPending(_ identifiers: String...) {
        cancelPending(identifiers)
    }

    /// Removes all pending notification requests.
    public func cancelAllPending() {
        center.removeAllPendingNotificationRequests()
    }

    /// Removes delivered notifications matching the given identifiers.
    public func removeDelivered(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Removes all delivered notifications from Notification Center.
    public func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - NotificationBuilder

/// A fluent builder for constructing and scheduling a local notification.
public final class NotificationBuilder {

    private let identifier: String
    private let center: UNUserNotificationCenter
    private let content = UNMutableNotificationContent()
    private var trigger: UNNotificationTrigger?

    init(identifier: String, center: UNUserNotificationCenter) {
        self.identifier = identifier
        self.center = center
    }

    // MARK: Content

    /// Sets the notification title.
    @discardableResult
    public func title(_ title: String) -> Self {
        content.title = title
        return self
    }

    /// Sets the notification subtitle.
    @discardableResult
    public func subtitle(_ subtitle: String) -> Self {
        content.subtitle = subtitle
        return self
    }

    /// Sets the notification body text.
    @discardableResult
    public func body(_ body: String) -> Self {
        content.body = body
        return self
    }

    /// Sets the badge number. Pass `nil` to leave the badge unchanged.
    @discardableResult
    public func badge(_ number: Int?) -> Self {
        content.badge = number.map { NSNumber(value: $0) }
        return self
    }

    /// Sets the notification sound. Defaults to `.default` when omitted.
    @discardableResult
    public func sound(_ sound: UNNotificationSound?) -> Self {
        content.sound = sound
        return self
    }

    /// Attaches custom data to the notification payload.
    @discardableResult
    public func userInfo(_ info: [AnyHashable: Any]) -> Self {
        content.userInfo = info
        return self
    }

    /// Sets the category identifier for actionable notifications.
    @discardableResult
    public func categoryIdentifier(_ id: String) -> Self {
        content.categoryIdentifier = id
        return self
    }

    /// Sets the thread identifier for notification grouping.
    @discardableResult
    public func threadIdentifier(_ id: String) -> Self {
        content.threadIdentifier = id
        return self
    }

    // MARK: Triggers

    /// Fires the notification after `seconds` from now.
    /// - Parameter repeats: Whether the trigger should repeat at this interval.
    @discardableResult
    public func after(seconds: TimeInterval, repeats: Bool = false) -> Self {
        trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(seconds, 1),
            repeats: repeats
        )
        return self
    }

    /// Fires the notification at the specified date components.
    /// - Parameter repeats: Whether the trigger should repeat (e.g., daily at 9 AM).
    @discardableResult
    public func at(dateComponents: DateComponents, repeats: Bool = false) -> Self {
        trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: repeats
        )
        return self
    }

    /// Fires the notification at the given `Date`.
    @discardableResult
    public func at(date: Date) -> Self {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        return self
    }

    /// Fires the notification daily at the specified hour and minute.
    @discardableResult
    public func daily(hour: Int, minute: Int = 0) -> Self {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )
        return self
    }

    /// Fires the notification weekly on the given weekday (1 = Sunday) at the specified time.
    @discardableResult
    public func weekly(weekday: Int, hour: Int, minute: Int = 0) -> Self {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )
        return self
    }

    // MARK: Commit

    /// Schedules the notification with the notification center.
    ///
    /// If no sound has been set, `.default` is applied automatically.
    /// If no trigger has been set, the notification fires after 1 second.
    ///
    /// - Throws: An error if the notification center rejects the request.
    public func commit() async throws {
        if content.sound == nil {
            content.sound = .default
        }
        let resolvedTrigger = trigger ?? UNTimeIntervalNotificationTrigger(
            timeInterval: 1,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: resolvedTrigger
        )
        try await center.add(request)
    }
}
