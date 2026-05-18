# NotificationScheduler

A fluent wrapper around `UNUserNotificationCenter` for scheduling, querying, and cancelling local notifications with a builder-style API.

## API

| Type / Method | Description |
|---|---|
| `NotificationScheduler.shared` | Shared singleton instance |
| `NotificationScheduler(center:)` | Init with a custom `UNUserNotificationCenter` |
| `requestAuthorization(options:)` | Request notification permissions; returns `Bool` |
| `authorizationStatus()` | Current `UNAuthorizationStatus` without prompting |
| `schedule(_:)` | Begin building a notification; returns `NotificationBuilder` |
| `pendingIdentifiers()` | List identifiers of pending notifications |
| `deliveredIdentifiers()` | List identifiers of delivered notifications |
| `cancelPending(_:)` | Cancel pending notifications by identifier |
| `cancelAllPending()` | Cancel all pending notifications |
| `removeDelivered(_:)` | Remove delivered notifications by identifier |
| `removeAllDelivered()` | Remove all delivered notifications |

### NotificationBuilder

| Method | Description |
|---|---|
| `title(_:)` | Set the notification title |
| `subtitle(_:)` | Set the subtitle |
| `body(_:)` | Set the body text |
| `badge(_:)` | Set the badge number (nil to leave unchanged) |
| `sound(_:)` | Set a custom sound (defaults to `.default`) |
| `userInfo(_:)` | Attach custom data dictionary |
| `categoryIdentifier(_:)` | Set category for actionable notifications |
| `threadIdentifier(_:)` | Set thread for notification grouping |
| `after(seconds:repeats:)` | Fire after a time interval |
| `at(dateComponents:repeats:)` | Fire at specific date components |
| `at(date:)` | Fire at an exact `Date` |
| `daily(hour:minute:)` | Repeat daily at the given time |
| `weekly(weekday:hour:minute:)` | Repeat weekly on a specific day and time |
| `commit()` | Schedule the notification (async throws) |

## Examples

```swift
import SwiftUtilsHelpers

let scheduler = NotificationScheduler.shared

// Request authorization on app launch
try await scheduler.requestAuthorization(options: [.alert, .sound, .badge])

// Schedule a one-shot reminder in 30 minutes
try await scheduler.schedule("water-reminder")
    .title("Hydration Check")
    .body("Time to drink some water!")
    .badge(1)
    .after(seconds: 1800)
    .commit()

// Schedule a daily standup reminder at 9:45 AM
try await scheduler.schedule("standup-daily")
    .title("Standup")
    .subtitle("#ios-team")
    .body("Daily standup starts in 15 minutes.")
    .daily(hour: 9, minute: 45)
    .commit()

// Schedule a weekly review every Monday at 2 PM
try await scheduler.schedule("weekly-review")
    .title("Weekly Review")
    .body("Review sprint progress and blockers.")
    .weekly(weekday: 2, hour: 14)
    .commit()

// Schedule at an exact date (e.g., a deadline)
let deadline = Calendar.current.date(
    from: DateComponents(year: 2026, month: 6, day: 1, hour: 10)
)!
try await scheduler.schedule("project-deadline")
    .title("Project Due")
    .body("Final submission deadline is today.")
    .sound(.defaultCritical)
    .at(date: deadline)
    .commit()

// Attach deep-link data for tap handling
try await scheduler.schedule("promo-offer")
    .title("Flash Sale!")
    .body("50% off all premium features — today only.")
    .categoryIdentifier("promo")
    .threadIdentifier("marketing")
    .userInfo(["deepLink": "app://promo/flash-sale-2026"])
    .after(seconds: 10)
    .commit()

// List and cancel
let pending = await scheduler.pendingIdentifiers()
print("Pending: \(pending)")

scheduler.cancelPending("water-reminder")
scheduler.cancelAllPending()

// Check authorization without prompting
let status = await scheduler.authorizationStatus()
if status == .denied {
    // Guide user to Settings
}
```
