# GradientBuilder

A declarative, chainable builder for `CAGradientLayer` with linear/radial support, presets, and UIImage rendering.

## API

| Method | Description |
|---|---|
| `.add(color:at:)` | Add a color stop (0-1 location) |
| `.direction(_:)` | Set gradient direction |
| `.radial(center:radius:)` | Switch to radial gradient |
| `.cornerRadius(_:)` | Round corners on the layer |
| `.build(in:)` | Build a `CAGradientLayer` |
| `.renderImage(size:)` | Render gradient to `UIImage` |
| `UIView.applyGradient(_:)` | One-liner extension |

### Presets

`.sunset`, `.ocean`, `.forest`, `.nightSky`

### Directions

`.topToBottom`, `.leftToRight`, `.topLeftToBottomRight`, `.custom(start:end:)`, and more.

## Examples

```swift
import SwiftUtilsUIUtilities

// Custom gradient with chaining
let layer = GradientBuilder()
    .add(color: .systemBlue, at: 0)
    .add(color: .systemPurple, at: 0.5)
    .add(color: .systemPink, at: 1)
    .direction(.topLeftToBottomRight)
    .cornerRadius(16)
    .build(in: view.bounds)
view.layer.insertSublayer(layer, at: 0)

// One-liner on a view
view.applyGradient(
    GradientBuilder()
        .add(color: .systemIndigo, at: 0)
        .add(color: .systemTeal, at: 1)
        .direction(.leftToRight)
)

// Use presets
let sunset = GradientBuilder.sunset.build(in: headerView.bounds)
let oceanImage = GradientBuilder.ocean.renderImage(size: CGSize(width: 300, height: 200))

// Radial gradient
let radial = GradientBuilder()
    .add(color: .white, at: 0)
    .add(color: .black, at: 1)
    .radial(center: CGPoint(x: 0.5, y: 0.5), radius: 0.5)
    .build(in: view.bounds)
```
