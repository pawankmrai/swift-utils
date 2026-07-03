# PasteboardManager

A type-safe wrapper around `UIPasteboard` that adds expiring items, local-only (non-cloud-synced) copies, and a closure-based change observer. Normalizes the string-keyed, `Any`-typed nature of `UIPasteboard` into small, typed methods for strings, URLs, images, and colors.

## API

| Type / Method | Description |
|---|---|
| `PasteboardManager.shared` | Shared manager backed by the general (system) pasteboard |
| `PasteboardManager()` | Create a manager around the general pasteboard |
| `PasteboardManager(named:create:)` | Create a manager around a named, app-specific pasteboard |
| `copy(_:expiresIn:localOnly:)` | Copy a `String`, `URL`, `UIImage`, or `UIColor` (overloaded) |
| `string()` | The current string on the pasteboard, if any |
| `url()` | The current URL, falling back to parsing the pasteboard string |
| `image()` | The current image on the pasteboard, if any |
| `color()` | The current color, unarchived from a prior `copy(_:)` call |
| `hasStrings` | Whether the pasteboard currently holds plain text |
| `hasURLs` | Whether the pasteboard currently holds a URL |
| `hasImages` | Whether the pasteboard currently holds an image |
| `itemCount` | The number of items currently on the pasteboard |
| `clear()` | Removes all items from the pasteboard |
| `onChange(_:)` | Register a closure called on the main queue whenever contents change; returns a `UUID` token |
| `removeChangeHandler(_:)` | Stop a previously registered change handler |

## Examples

```swift
import SwiftUtilsHelpers

let pasteboard = PasteboardManager.shared

// Copy plain text
pasteboard.copy("Hello, world!")
let text = pasteboard.string() // "Hello, world!"

// Copy a URL — reads back as a URL even if another app writes plain text
pasteboard.copy(URL(string: "https://example.com/invite/abc123")!)
if let link = pasteboard.url() {
    print("Copied invite link: \(link)")
}

// Copy an image
let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
let snapshot = renderer.image { ctx in
    UIColor.systemTeal.setFill()
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
}
pasteboard.copy(snapshot)

// Copy a brand color for a design-handoff tool
pasteboard.copy(UIColor.systemIndigo)
if let brandColor = pasteboard.color() {
    print("Copied color: \(brandColor)")
}

// Copy a one-time login code that self-clears after 30 seconds
// and never syncs to the user's other devices via Universal Clipboard.
pasteboard.copy("482913", expiresIn: 30, localOnly: true)

// Check what's on the pasteboard before deciding how to handle a paste action
if pasteboard.hasURLs {
    // Offer "Open Link" in a context menu
} else if pasteboard.hasImages {
    // Offer "Paste Image"
} else if pasteboard.hasStrings {
    // Offer "Paste Text"
}

// Clear sensitive content after use
pasteboard.copy("temporary-otp-551239")
// ... user pastes it into a form ...
pasteboard.clear()

// Observe pasteboard changes, e.g. to detect a copied verification code
// and offer to auto-fill it.
let token = pasteboard.onChange {
    guard let text = PasteboardManager.shared.string(),
          text.range(of: #"^\d{6}$"#, options: .regularExpression) != nil else { return }
    print("Detected a 6-digit code on the pasteboard: \(text)")
}

// Stop observing when the view disappears
pasteboard.removeChangeHandler(token)

// Use an app-specific named pasteboard to pass data between an app
// and its extension without touching the shared system clipboard.
let handoff = PasteboardManager(named: UIPasteboard.Name("com.myapp.handoff"))
handoff.copy("draft-id-9931")
let draftID = handoff.string()
```
