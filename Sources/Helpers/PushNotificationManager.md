# PushNotificationManager

Coordinates the remote (push) notification lifecycle — requesting authorization, registering with APNs, capturing the device token, and routing incoming payloads to per-category handlers — so `AppDelegate`/`SceneDelegate` boilerplate stays out of your feature code. Complements [`NotificationScheduler`](NotificationScheduler.md), which handles *local* notification scheduling instead of the remote-notification lifecycle.

## API

| Type / Method / Property | Description |
|---|---|
| `PushNotificationPayload` | Parsed, type-safe view over a notification's raw `userInfo` dictionary |
| `PushNotificationPayload.init(userInfo:)` | Parses `title`, `body`, `category`, `threadIdentifier`, `badge`, `sound`, and `customData` from `aps` and top-level keys |
| `PushNotificationManager.shared` | Shared singleton |
| `PushNotificationManager.init()` | Creates an independent, testable instance |
| `PushNotificationManager.deviceToken` | Current APNs token as a lowercase hex string, or `nil` |
| `PushNotificationManager.deviceTokenData` | Raw `Data` token most recently reported by the system |
| `PushNotificationManager.registrationError` | Most recent registration error, if any |
| `PushNotificationManager.requestAuthorization(options:)` | Async — requests alert/badge/sound permission, returns whether granted |
| `PushNotificationManager.authorizationStatus()` | Async — current `UNAuthorizationStatus` |
| `PushNotificationManager.registerForRemoteNotifications()` | Main actor — triggers APNs registration |
| `PushNotificationManager.handleDeviceToken(_:)` | Converts token `Data` to hex, stores it, notifies `tokenUpdates()` subscribers |
| `PushNotificationManager.handleRegistrationFailure(_:)` | Records a registration failure and clears the stored token |
| `PushNotificationManager.tokenUpdates()` | `AsyncStream<String>` that yields the current token (if any) and every subsequent update |
| `PushNotificationManager.onNotification(category:handler:)` | Registers a handler for payloads whose `aps.category` matches |
| `PushNotificationManager.onUnhandledNotification(_:)` | Registers a fallback handler for uncategorized or unmatched payloads |
| `PushNotificationManager.handle(userInfo:)` | Parses `userInfo` and dispatches it to the matching handler; returns whether one was found |
| `PushNotificationManager.removeAllHandlers()` | Clears all category and default handlers |
| `PushNotificationManager.reset()` | Clears the stored token, error, and pending `tokenUpdates()` subscribers |

## Examples

### Wiring up in `AppDelegate`

```swift
import SwiftUtilsHelpers
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        PushNotificationManager.shared.onNotification(category: "CHAT_MESSAGE") { payload in
            if let conversationId = payload.customData["conversationId"] {
                Router.shared.openConversation(id: conversationId)
            }
        }
        PushNotificationManager.shared.onUnhandledNotification { payload in
            print("Unrouted push: \(payload.title ?? "") — \(payload.body ?? "")")
        }

        Task {
            let granted = try? await PushNotificationManager.shared.requestAuthorization()
            if granted == true {
                await PushNotificationManager.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = PushNotificationManager.shared.handleDeviceToken(deviceToken)
        Task { await MyBackend.uploadPushToken(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.handleRegistrationFailure(error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        PushNotificationManager.shared.handle(userInfo: userInfo) ? .newData : .noData
    }
}
```

### Routing inside a `UNUserNotificationCenterDelegate`

```swift
import SwiftUtilsHelpers
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        PushNotificationManager.shared.handle(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }
}
```

### Observing the device token with `AsyncStream`

Handy for a settings screen that displays the current token, or for retrying an upload after a network failure.

```swift
Task {
    for await token in PushNotificationManager.shared.tokenUpdates() {
        print("Device token updated: \(token)")
        await MyBackend.uploadPushToken(token)
    }
}
```

### Parsing a payload directly (e.g. in a Notification Service Extension)

```swift
import SwiftUtilsHelpers

func didReceive(_ request: UNNotificationRequest) {
    let payload = PushNotificationPayload(userInfo: request.content.userInfo)
    print(payload.title ?? "(no title)", payload.body ?? "")
    print("Deep link screen:", payload.customData["screen"] ?? "none")
}
```

### Signing out and clearing push state

```swift
func handleSignOut() {
    PushNotificationManager.shared.removeAllHandlers()
    PushNotificationManager.shared.reset()
}
```

### Unit testing with an isolated instance

```swift
let manager = PushNotificationManager()

let token = manager.handleDeviceToken(Data([0xDE, 0xAD, 0xBE, 0xEF]))
XCTAssertEqual(token, "deadbeef")

var routed = false
manager.onNotification(category: "PROMO") { _ in routed = true }
manager.handle(userInfo: ["aps": ["alert": "Sale!", "category": "PROMO"]])
XCTAssertTrue(routed)
```
