# AnimationUtilities

Declarative, chainable UIView animation builder with presets, sequential animation chains, and convenience extensions for common effects.

## API

| Type / Method | Description |
|---|---|
| `AnimationConfig` | Value-type builder for animation parameters |
| `.duration(_:)` | Set animation duration in seconds |
| `.delay(_:)` | Set delay before animation starts |
| `.springDamping(_:)` | Spring damping ratio (0…1); < 1 produces bounce |
| `.initialVelocity(_:)` | Initial spring velocity |
| `.options(_:)` | UIView.AnimationOptions flags |
| `.curve(_:)` | Timing curve (easeIn, easeOut, etc.) |
| `.animate(_:completion:)` | Execute the animation |
| `.animate(_:) async` | Execute and await completion |
| `.quickFade` | Preset: 0.2s ease-out |
| `.spring` | Preset: 0.5s with slight bounce |
| `.bouncy` | Preset: 0.6s with strong bounce |
| `.smooth` | Preset: 0.35s ease-in-out |
| `UIView.fadeIn(...)` | Fade view in from alpha 0 |
| `UIView.fadeOut(...)` | Fade view out to alpha 0 |
| `UIView.popScale(...)` | Scale-up-then-back spring effect |
| `UIView.shake(...)` | Horizontal shake (validation errors) |
| `UIView.slideIn(from:...)` | Slide in from an edge with spring |
| `SlideEdge` | `.top`, `.bottom`, `.leading`, `.trailing` |
| `AnimationSequence` | Run chained animations sequentially |
| `.step(config:_:)` | Add a step with full config |
| `.step(duration:_:)` | Add a step with just duration |
| `.run(completion:)` | Execute all steps in order |
| `.run() async` | Execute all steps with async/await |

## Examples

```swift
import SwiftUtilsUIUtilities

// Simple fade in
view.fadeIn(duration: 0.3)

// Fade out with completion
view.fadeOut(duration: 0.25) { _ in
    view.removeFromSuperview()
}

// Pop scale on button tap
button.popScale(to: 1.15)

// Shake on validation error
emailField.shake(intensity: 12, duration: 0.4)

// Slide in from bottom
card.slideIn(from: .bottom, offset: 200, duration: 0.5)

// Custom animation with builder
AnimationConfig()
    .duration(0.35)
    .springDamping(0.7)
    .curve(.easeOut)
    .animate { view.alpha = 1; view.transform = .identity }

// Use presets
AnimationConfig.bouncy
    .animate { popup.transform = .identity }

// Async/await
let finished = await AnimationConfig.spring
    .duration(0.4)
    .animate { view.frame.origin.y = 0 }

// Sequential animation chain
AnimationSequence()
    .step(duration: 0.2) { title.alpha = 1 }
    .step(duration: 0.3) { subtitle.alpha = 1 }
    .step(config: .spring) { button.transform = .identity }
    .run { print("All done") }

// Async sequence
await AnimationSequence()
    .step(config: .quickFade) { overlay.alpha = 0 }
    .step(duration: 0.3) { content.transform = .identity }
    .run()
```
