# KeyboardObserver

An observer for the system keyboard's height, visibility, and animation timing — with ready-made adjustments for `UIScrollView` (UIKit) and any SwiftUI view via `.keyboardAdaptive()`.

## API

| Type / Method | Description |
|---|---|
| `KeyboardObserver` | `ObservableObject` that publishes keyboard state |
| `.shared` | App-wide singleton instance |
| `.keyboardHeight` | Current keyboard height in points (`0` when hidden) |
| `.isVisible` | Whether the keyboard is currently showing |
| `.animationDuration` | Duration of the keyboard's current show/hide animation |
| `.animationOptions` | `UIView.AnimationOptions` matching the keyboard's curve |
| `.heightStream` | `AsyncStream<CGFloat>` of height updates |
| `UIScrollView.swiftUtils_avoidKeyboard(using:)` | Auto-adjusts bottom content inset to avoid the keyboard |
| `View.keyboardAdaptive(extraPadding:observer:)` | SwiftUI modifier that pads content above the keyboard |

## Examples

```swift
import SwiftUtilsUIUtilities
```

### SwiftUI — pad content above the keyboard

```swift
struct ChatView: View {
    @State private var message = ""

    var body: some View {
        VStack {
            ScrollView { /* messages */ }
            TextField("Message", text: $message)
        }
        .keyboardAdaptive(extraPadding: 8)
    }
}
```

### UIKit — keep a scroll view's content clear of the keyboard

```swift
final class ChatViewController: UIViewController {
    @IBOutlet var scrollView: UIScrollView!
    private var keyboardCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboardCancellable = scrollView.swiftUtils_avoidKeyboard()
    }
}
```

### Observing state directly

```swift
let observer = KeyboardObserver.shared

observer.$isVisible
    .sink { visible in
        sendButton.isHidden = !visible
    }
    .store(in: &cancellables)

observer.$keyboardHeight
    .sink { height in
        bottomConstraint.constant = height
        UIView.animate(withDuration: observer.animationDuration) {
            view.layoutIfNeeded()
        }
    }
    .store(in: &cancellables)
```

### Swift concurrency — reacting via `AsyncStream`

```swift
Task {
    for await height in KeyboardObserver.shared.heightStream {
        print("Keyboard height: \(height)")
    }
}
```

### Scoped, testable usage

```swift
// Inject a dedicated observer instead of the shared singleton,
// useful for previews, tests, or isolated screens.
let observer = KeyboardObserver()
someView.keyboardAdaptive(observer: observer)
```
