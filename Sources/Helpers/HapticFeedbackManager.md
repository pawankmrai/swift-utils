# HapticFeedbackManager

A lightweight, thread-safe wrapper around UIKit's haptic feedback generators providing a clean, expressive API for triggering haptics in iOS apps. Supports one-liner triggers, prepared generators for low-latency scenarios, and custom pattern playback.

## API

| Type / Method | Description |
|---|---|
| `HapticFeedbackManager.shared` | Shared singleton instance |
| `HapticFeedbackManager()` | Create a new independent manager instance |
| `isEnabled` | Bool property to globally enable/disable haptics |
| `supportsHaptics` | Whether the current device supports haptic feedback |
| `impact(_:)` | Trigger an impact haptic with a given style |
| `impact(_:intensity:)` | Trigger an impact with custom intensity (0.0–1.0) |
| `notification(_:)` | Trigger a notification haptic (success/warning/error) |
| `selection()` | Trigger a subtle selection tick |
| `prepare()` | Prepare all generators for immediate use |
| `prepare(_:)` | Prepare a specific impact style generator |
| `playPattern(_:)` | Play a sequence of haptic elements (async) |
| `doubleTap(style:)` | Convenience: two quick taps (async) |
| `escalate()` | Convenience: light → medium → heavy (async) |
| `heartbeat()` | Convenience: two-pulse heartbeat pattern (async) |

### ImpactStyle

| Case | Description |
|---|---|
| `.light` | Subtle, lightweight impact |
| `.medium` | Standard impact (default) |
| `.heavy` | Strong, prominent impact |
| `.soft` | Soft, cushioned impact |
| `.rigid` | Sharp, precise impact |

### NotificationType

| Case | Description |
|---|---|
| `.success` | Positive outcome feedback |
| `.warning` | Cautionary feedback |
| `.error` | Failure or error feedback |

### PatternElement

| Case | Description |
|---|---|
| `.impact(ImpactStyle, intensity:)` | An impact with optional custom intensity |
| `.notification(NotificationType)` | A notification haptic |
| `.selection` | A selection tick |
| `.pause(TimeInterval)` | A delay between elements (seconds) |

## Examples

```swift
import SwiftUtilsHelpers

let haptics = HapticFeedbackManager.shared

// Simple one-liner triggers
haptics.impact(.medium)            // Standard tap
haptics.impact(.heavy)             // Strong tap
haptics.notification(.success)     // Success confirmation
haptics.notification(.error)       // Error alert
haptics.selection()                // Picker change tick

// Custom intensity (0.0 to 1.0)
haptics.impact(.rigid, intensity: 0.3)  // Gentle rigid tap
haptics.impact(.heavy, intensity: 1.0)  // Maximum heavy impact

// Prepare for low-latency use (call on touchDown)
haptics.prepare(.medium)

// Disable/enable globally (e.g., user preference)
haptics.isEnabled = UserDefaults.standard.bool(forKey: "hapticsEnabled")

// Check device support
if haptics.supportsHaptics {
    haptics.impact(.medium)
} else {
    // Fallback to visual feedback
}

// Play a custom pattern
await haptics.playPattern([
    .impact(.light),
    .pause(0.1),
    .impact(.medium),
    .pause(0.1),
    .impact(.heavy),
    .pause(0.2),
    .notification(.success)
])

// Built-in convenience patterns
await haptics.doubleTap(style: .rigid)   // Confirm action
await haptics.escalate()                  // Attention grabber
await haptics.heartbeat()                 // Pulse animation feedback

// Use in a SwiftUI button
struct ConfirmButton: View {
    var body: some View {
        Button("Confirm Purchase") {
            Task {
                await HapticFeedbackManager.shared.doubleTap()
            }
        }
    }
}

// Use with a long-press gesture for escalation
struct LongPressView: View {
    var body: some View {
        Circle()
            .onLongPressGesture(minimumDuration: 0.5) {
                Task { await HapticFeedbackManager.shared.escalate() }
            } onPressingChanged: { pressing in
                if pressing {
                    HapticFeedbackManager.shared.prepare()
                }
            }
    }
}

// Custom pattern for a game power-up
let powerUpPattern: [HapticFeedbackManager.PatternElement] = [
    .impact(.soft, intensity: 0.3),
    .pause(0.05),
    .impact(.medium, intensity: 0.5),
    .pause(0.05),
    .impact(.heavy, intensity: 0.7),
    .pause(0.05),
    .impact(.rigid, intensity: 1.0),
    .pause(0.1),
    .notification(.success)
]
await haptics.playPattern(powerUpPattern)
```
