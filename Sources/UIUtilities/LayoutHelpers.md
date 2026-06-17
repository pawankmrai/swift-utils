# LayoutHelpers

A fluent, chainable Auto Layout builder for UIKit. Pin edges, center, size, match dimensions, and set priorities — all without writing raw `NSLayoutConstraint` boilerplate, and without giving up the ability to inspect or defer activation.

## API

| Type / Member | Description |
|---|---|
| `UIView.layout` | Starts a chainable `LayoutAnchorBuilder` for the view |
| `.pin(_:to:insets:)` | Pin selected edges to a view or layout guide |
| `.center(in:offset:)` | Center the view in a view or layout guide |
| `.size(width:height:)` | Fixed-size constraints |
| `.aspectRatio(_:)` | Constrain width ÷ height to a ratio |
| `.match(_:of:multiplier:constant:)` | Match width/height to another view's dimension |
| `.priority(_:)` | Apply a priority to every constraint built so far |
| `.constraints()` | Return constraints without activating |
| `.activate()` | Activate and return the constraints |
| `LayoutEdges` | `.top`, `.leading`, `.trailing`, `.bottom`, `.all`, `.horizontal`, `.vertical` |
| `LayoutDimension` | `.width`, `.height` |
| `NSDirectionalEdgeInsets.all(_:)` | Equal insets on all edges |
| `NSDirectionalEdgeInsets.symmetric(horizontal:vertical:)` | Mirrored insets |
| `UIView.pinToSuperview(_:insets:)` | One-liner: pin to superview, returns `nil` if orphaned |
| `UIView.centerInSuperview(offset:)` | One-liner: center in superview, returns `nil` if orphaned |
| `LayoutAnchorProviding` | Protocol uniting `UIView` and `UILayoutGuide` as pinnable targets |

## Examples

```swift
import SwiftUtilsUIUtilities

// Pin a card to its container with symmetric insets, then fix its height
let card = UIView()
container.addSubview(card)
card.layout
    .pin(.horizontal, to: container, insets: .symmetric(horizontal: 16))
    .pin(.top, to: container.safeAreaLayoutGuide, insets: .all(12))
    .size(height: 120)
    .activate()

// One-liner full-bleed pin to superview
imageView.pinToSuperview()

// Pin with insets on just two edges
banner.pinToSuperview(.horizontal, insets: .all(8))

// Center a spinner, offset slightly above the visual center
spinner.centerInSuperview(offset: CGPoint(x: 0, y: -24))

// Maintain a 16:9 aspect ratio
thumbnail.layout
    .pin(.horizontal, to: container)
    .aspectRatio(16.0 / 9.0)
    .activate()

// Match a sidebar's width to 30% of its container, with a low priority
// fallback so it can shrink under pressure
sidebar.layout
    .match(.width, of: container, multiplier: 0.3)
    .priority(.defaultHigh)
    .activate()

// Defer activation: inspect constraints before committing
let pending = badge.layout
    .pin(.top, to: container, insets: .all(8))
    .pin(.trailing, to: container, insets: .all(8))
    .constraints()
print(pending.count) // 2
NSLayoutConstraint.activate(pending)
```
