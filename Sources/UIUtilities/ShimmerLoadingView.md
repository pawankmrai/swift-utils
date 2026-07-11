# ShimmerLoadingView

Animated shimmer / skeleton placeholder views for loading states. Ships with a
`UIView` subclass (`ShimmerLoadingView`) for UIKit skeleton screens, and a
`shimmering(isActive:)` `ViewModifier` for redacting and animating any
SwiftUI view while its content loads.

## API

| Type / Method | Description |
|---|---|
| `ShimmerLoadingView(configuration:)` | UIKit view that renders a looping gradient sweep over a base color |
| `.startShimmering()` | Start (or restart) the shimmer animation |
| `.stopShimmering()` | Stop the animation, leaving the resting base color visible |
| `.isShimmering` | Whether the animation is currently running |
| `.configuration` | Get/set the active `ShimmerConfiguration`; reassigning while shimmering restarts the animation |
| `ShimmerConfiguration` | `baseColor`, `highlightColor`, `duration`, `pauseBetweenPasses`, `direction`, `bandWidth` |
| `ShimmerConfiguration.default` | Subtle system-gray preset |
| `ShimmerDirection` | `.leftToRight`, `.rightToLeft`, `.topToBottom`, `.bottomToTop` |
| `View.shimmering(isActive:duration:)` | SwiftUI modifier that redacts content and animates a shimmer highlight across it |

## Examples

### UIKit: skeleton avatar and text lines

```swift
import SwiftUtilsUIUtilities

let avatar = ShimmerLoadingView()
avatar.layer.cornerRadius = 24
avatar.frame = CGRect(x: 16, y: 16, width: 48, height: 48)
view.addSubview(avatar)
avatar.startShimmering()

let titleLine = ShimmerLoadingView()
titleLine.layer.cornerRadius = 4
titleLine.frame = CGRect(x: 76, y: 20, width: 160, height: 12)
view.addSubview(titleLine)
titleLine.startShimmering()

// Once real data arrives:
func didLoadProfile(_ profile: Profile) {
    avatar.stopShimmering()
    titleLine.stopShimmering()
    avatar.removeFromSuperview()
    titleLine.removeFromSuperview()
    render(profile)
}
```

### UIKit: custom colors and direction

```swift
let bannerSkeleton = ShimmerLoadingView(configuration: ShimmerConfiguration(
    baseColor: .secondarySystemBackground,
    highlightColor: .systemBackground,
    duration: 1.5,
    pauseBetweenPasses: 0.2,
    direction: .topToBottom,
    bandWidth: 0.4
))
bannerSkeleton.frame = bannerContainer.bounds
bannerContainer.addSubview(bannerSkeleton)
bannerSkeleton.startShimmering()
```

### UIKit: reusing one view across a table cell's lifecycle

```swift
final class ArticleCell: UITableViewCell {
    private let shimmer = ShimmerLoadingView()

    func configure(with article: Article?) {
        guard let article else {
            titleLabel.isHidden = true
            shimmer.isHidden = false
            shimmer.startShimmering()
            return
        }
        shimmer.stopShimmering()
        shimmer.isHidden = true
        titleLabel.isHidden = false
        titleLabel.text = article.title
    }
}
```

### SwiftUI: redact and shimmer a single view

```swift
import SwiftUtilsUIUtilities
import SwiftUI

struct ProfileHeader: View {
    let profile: Profile?

    var body: some View {
        HStack {
            Circle()
                .fill(.gray.opacity(0.3))
                .frame(width: 48, height: 48)
                .shimmering(isActive: profile == nil)

            Text(profile?.name ?? "Placeholder Name")
                .font(.headline)
                .shimmering(isActive: profile == nil)
        }
    }
}
```

### SwiftUI: list of skeleton rows while loading

```swift
struct FeedView: View {
    @State private var items: [FeedItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ForEach(0..<6, id: \.self) { _ in
                    FeedRowPlaceholder()
                        .shimmering(isActive: true)
                }
            } else {
                ForEach(items) { item in
                    FeedRow(item: item)
                }
            }
        }
        .task {
            items = await loadFeed()
            isLoading = false
        }
    }
}
```

### SwiftUI: custom sweep duration

```swift
Text("Loading balance…")
    .redacted(reason: .placeholder)
    .shimmering(isActive: true, duration: 0.8)
```
