# ReviewPromptManager

Tracks usage signals on-device and decides when it's appropriate to ask a user for an App Store review via `SKStoreReviewController`, so you never have to hand-roll the throttling logic yourself. Prompts respect a minimum number of significant events, a minimum install age, a minimum cooldown between prompts, and (optionally) never repeat for the same app version.

## API

| Type / Method / Property | Description |
|---|---|
| `ReviewPromptCriteria` | Value type holding the eligibility thresholds |
| `ReviewPromptCriteria.default` | 5 significant events, 3 days installed, 90-day cooldown, once per version |
| `ReviewPromptCriteria.init(minSignificantEvents:minDaysSinceFirstLaunch:minDaysBetweenPrompts:promptOncePerAppVersion:)` | Custom thresholds |
| `ReviewPromptManager.shared` | Shared singleton |
| `ReviewPromptManager.init(criteria:userDefaults:bundle:now:)` | Custom initialiser — inject `UserDefaults`, `Bundle`, and a clock for testing |
| `ReviewPromptManager.criteria` | Mutable — tune throttling at runtime |
| `ReviewPromptManager.firstLaunchDate` | Date the manager first recorded activity |
| `ReviewPromptManager.significantEventCount` | Number of events recorded so far |
| `ReviewPromptManager.lastPromptDate` | Date of the most recent prompt, or `nil` |
| `ReviewPromptManager.lastPromptedVersion` | App version at the last prompt, or `nil` |
| `ReviewPromptManager.currentAppVersion` | `CFBundleShortVersionString`, or `"unknown"` |
| `ReviewPromptManager.isEligible` | `true` if every criterion is currently satisfied — no side effects |
| `ReviewPromptManager.recordSignificantEvent()` | Increments the event counter |
| `ReviewPromptManager.requestReviewIfEligible(in:)` | iOS 15+, main actor — presents `SKStoreReviewController` if eligible, then records the prompt |
| `ReviewPromptManager.markPrompted()` | Records a prompt without presenting UI (useful for tests or custom rating flows) |
| `ReviewPromptManager.reset()` | Clears all persisted state |

## Examples

### Recording significant events

Call this wherever the user completes an action that indicates real value delivered — not on every launch.

```swift
import SwiftUtilsHelpers

func onExportCompleted() {
    ReviewPromptManager.shared.recordSignificantEvent()
}

func onWorkoutStreakHit(days: Int) {
    if days == 7 {
        ReviewPromptManager.shared.recordSignificantEvent()
    }
}
```

### Requesting a review at a safe point in the UI

The best place to ask is right after a moment of success — never mid-task or on an error screen.

```swift
import SwiftUtilsHelpers
import UIKit

final class SuccessViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let scene = view.window?.windowScene else { return }
        ReviewPromptManager.shared.requestReviewIfEligible(in: scene)
    }
}
```

### SwiftUI

```swift
import SwiftUI
import SwiftUtilsHelpers

struct OrderConfirmationView: View {
    var body: some View {
        VStack {
            Text("Order placed! 🎉")
        }
        .onAppear {
            ReviewPromptManager.shared.recordSignificantEvent()
        }
        .task {
            guard let scene = await UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }
            ReviewPromptManager.shared.requestReviewIfEligible(in: scene)
        }
    }
}
```

### Customizing the criteria

```swift
ReviewPromptManager.shared.criteria = ReviewPromptCriteria(
    minSignificantEvents: 10,
    minDaysSinceFirstLaunch: 7,
    minDaysBetweenPrompts: 120,
    promptOncePerAppVersion: true
)
```

### Checking eligibility without prompting

Useful for surfacing your own "Enjoying the app?" banner before falling back to the system sheet.

```swift
if ReviewPromptManager.shared.isEligible {
    showCustomRatingBanner()
}
```

### Resetting state (debug menu)

```swift
#if DEBUG
Button("Reset review prompt state") {
    ReviewPromptManager.shared.reset()
}
#endif
```

### Unit testing with a mock clock and isolated defaults

```swift
var currentDate = Date()
let testDefaults = UserDefaults(suiteName: "test-suite")!

let manager = ReviewPromptManager(
    criteria: ReviewPromptCriteria(minSignificantEvents: 1, minDaysSinceFirstLaunch: 0, minDaysBetweenPrompts: 0),
    userDefaults: testDefaults,
    now: { currentDate }
)

manager.recordSignificantEvent()
XCTAssertTrue(manager.isEligible)

manager.markPrompted()
XCTAssertFalse(manager.isEligible) // per-version throttle kicks in
```
