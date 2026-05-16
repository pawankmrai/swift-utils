# DebounceThrottle

Thread-safe `Debouncer` and `Throttler` for rate-limiting closure execution.

## API

| Type | Description |
|---|---|
| `Debouncer(delay:queue:)` | Waits for a quiet period before firing |
| `Throttler(interval:mode:queue:)` | Caps execution frequency |
| `ThrottleMode` | `.leading`, `.trailing`, `.leadingAndTrailing` |

## Examples

```swift
import SwiftUtilsConcurrency

// Debounce — fires 0.3s after the user stops typing
let debouncer = Debouncer(delay: 0.3)

textField.addAction(UIAction { _ in
    debouncer.debounce {
        viewModel.search(query: textField.text ?? "")
    }
}, for: .editingChanged)

// Cancel a pending debounce
debouncer.cancel()

// Throttle — fires at most once per 0.5s
let throttler = Throttler(interval: 0.5, mode: .leadingAndTrailing)

scrollView.delegate = self
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    throttler.throttle {
        updateParallaxEffect()
    }
}

// Leading mode — fires immediately, then ignores for the interval
let leadingThrottler = Throttler(interval: 1.0, mode: .leading)

// Trailing mode — fires once at the end of the interval
let trailingThrottler = Throttler(interval: 1.0, mode: .trailing)

// Custom queue
let bgDebouncer = Debouncer(delay: 0.5, queue: .global(qos: .background))
```
