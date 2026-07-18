# ShareSheetPresenter

A convenience wrapper around `UIActivityViewController` that removes the usual boilerplate around iPad popover anchoring, activity exclusion, and completion handling. Share items are expressed as a typed `ShareItem` enum instead of raw `Any` values.

## API

| Type / Method | Description |
|---|---|
| `ShareItem` | Enum of shareable content: `.text(String)`, `.url(URL)`, `.image(UIImage)`, `.file(URL)` |
| `ShareSheetPresenter.Result` | Outcome of a presentation: `completed`, `activityType`, `error` |
| `present(_:from:sourceView:sourceRect:excludedActivityTypes:applicationActivities:completion:)` | Present a share sheet, optionally anchored to a source view for iPad popovers |
| `present(_:from:barButtonItem:excludedActivityTypes:applicationActivities:completion:)` | Present a share sheet anchored to a `UIBarButtonItem` (e.g. a nav bar share button) |
| `presentText(_:from:sourceView:completion:)` | Convenience for sharing a single string |
| `presentURL(_:from:sourceView:completion:)` | Convenience for sharing a single URL |
| `presentImage(_:from:sourceView:completion:)` | Convenience for sharing or saving a single image |

## Examples

```swift
import SwiftUtilsHelpers

// Share plain text and a link together
ShareSheetPresenter.present(
    [.text("Check out this app!"), .url(URL(string: "https://apps.apple.com/app/id123456789")!)],
    from: self,
    sourceView: shareButton
) { result in
    if result.completed {
        print("Shared via \(result.activityType?.rawValue ?? "unknown")")
    } else {
        print("Share sheet dismissed without sharing")
    }
}

// Share an exported file (e.g. a CSV report generated on disk)
let exportURL = try makeCSVExport()
ShareSheetPresenter.present([.file(exportURL)], from: self, sourceView: exportButton)

// Share a rendered image (e.g. a snapshot of a chart or receipt)
let snapshot = chartView.asImage()
ShareSheetPresenter.presentImage(snapshot, from: self, sourceView: shareIconView)

// Anchor to a navigation bar share button on iPad
@objc func shareTapped(_ sender: UIBarButtonItem) {
    ShareSheetPresenter.present(
        [.url(shareableLink)],
        from: self,
        barButtonItem: sender
    )
}

// Hide activities that don't make sense for this content
ShareSheetPresenter.present(
    [.text(referralCode)],
    from: self,
    sourceView: shareButton,
    excludedActivityTypes: [.assignToContact, .print, .saveToCameraRoll]
)

// One-line convenience for the common "share this link" case
ShareSheetPresenter.presentURL(productPageURL, from: self, sourceView: shareButton)

// Add a custom in-app activity alongside the system ones, e.g. "Save to Favorites"
ShareSheetPresenter.present(
    [.text(articleSummary), .url(articleURL)],
    from: self,
    sourceView: shareButton,
    applicationActivities: [SaveToFavoritesActivity(articleID: article.id)]
)

// SwiftUI: wrap the presentation behind a Boolean binding
struct ShareButton: View {
    let url: URL
    @State private var isPresenting = false

    var body: some View {
        Button("Share") { isPresenting = true }
            .background(ShareSheetRepresentable(isPresented: $isPresenting, items: [.url(url)]))
    }
}

private struct ShareSheetRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let items: [ShareItem]

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard isPresented, uiViewController.presentedViewController == nil else { return }
        ShareSheetPresenter.present(items, from: uiViewController, sourceView: uiViewController.view) { _ in
            isPresented = false
        }
    }
}
```
