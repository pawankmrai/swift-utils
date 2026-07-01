# ToastPresenter

A lightweight, queue-based toast/banner presenter for UIKit. Shows styled, auto-dismissing status messages over any container view, one at a time, with tap-to-dismiss and swipe-to-dismiss support.

## API

| Type / Method | Description |
|---|---|
| `ToastPresenter.shared` | Convenience app-wide singleton instance |
| `ToastPresenter()` | Create an independent presenter instance |
| `.configure(container:)` | Set the view toasts are presented over |
| `.show(_ configuration: ToastConfiguration)` | Queue a fully-configured toast |
| `.show(_ message:style:position:duration:)` | Queue a simple text toast |
| `.dismissCurrent()` | Dismiss the visible toast and advance the queue |
| `.clearQueue()` | Remove all pending (not-yet-shown) toasts |
| `.queuedCount` | Number of toasts waiting to be shown |
| `.isShowingToast` | Whether a toast is currently visible |
| `ToastConfiguration` | `message`, `style`, `position`, `duration`, `isSwipeToDismissEnabled`, `onTap` |
| `ToastStyle` | `.info`, `.success`, `.warning`, `.error`, `.custom(background:foreground:icon:)` |
| `ToastPosition` | `.top`, `.bottom` |

## Examples

```swift
import SwiftUtilsUIUtilities

// One-time setup, e.g. in a root view controller
ToastPresenter.shared.configure(container: view)

// Simple text toast
ToastPresenter.shared.show("Saved successfully", style: .success)

// Longer-lived error toast anchored to the top
ToastPresenter.shared.show(
    "Connection lost",
    style: .error,
    position: .top,
    duration: 4
)

// Fully configured toast with a tap action
let configuration = ToastConfiguration(
    message: "Message archived",
    style: .info,
    duration: 3,
    onTap: {
        print("Undo tapped")
    }
)
ToastPresenter.shared.show(configuration)

// Multiple toasts are queued and shown one after another
ToastPresenter.shared.show("Step 1 complete", style: .success)
ToastPresenter.shared.show("Step 2 complete", style: .success)
ToastPresenter.shared.show("All steps complete", style: .success)

// A persistent toast that requires manual dismissal
ToastPresenter.shared.show(
    ToastConfiguration(message: "Uploading… tap to cancel", duration: 0, onTap: {
        cancelUpload()
    })
)

// Custom styling
let brandStyle = ToastStyle.custom(
    background: UIColor(named: "BrandPurple") ?? .systemPurple,
    foreground: .white,
    icon: UIImage(systemName: "sparkles")
)
ToastPresenter.shared.show("Welcome back!", style: brandStyle)

// Using an isolated instance instead of the shared singleton (e.g. in tests
// or a modal flow with its own container)
let modalToaster = ToastPresenter()
modalToaster.configure(container: modalView)
modalToaster.show("Draft saved", style: .success, position: .top)
```
