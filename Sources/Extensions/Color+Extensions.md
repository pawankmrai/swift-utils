# Color+Extensions

Hex initialization, RGBA/HSBA extraction, color manipulation (lighten, darken, blend, saturate), and WCAG accessibility contrast checking for `UIColor`.

## API

| Method / Property | Description |
|---|---|
| `UIColor(hex:)` | Failable init from hex string (3, 4, 6, or 8 digit) |
| `toHex(includeAlpha:)` | Convert color to `#RRGGBB` or `#RRGGBBAA` string |
| `rgbaComponents` | Tuple of `(red, green, blue, alpha)` as `CGFloat` 0…1 |
| `hsbaComponents` | Tuple of `(hue, saturation, brightness, alpha)` as `CGFloat` |
| `luminance` | W3C relative luminance (0 = darkest, 1 = lightest) |
| `isLight` | `true` if luminance > 0.5 |
| `lightened(by:)` | Return a lighter version (default 0.2) |
| `darkened(by:)` | Return a darker version (default 0.2) |
| `withAlpha(_:)` | Return color with a new alpha value |
| `saturated(to:)` | Return color adjusted to given saturation (0…1) |
| `blended(with:fraction:)` | Blend with another color by fraction (0…1) |
| `complementary` | The opposite color on the color wheel |
| `contrastRatio(with:)` | WCAG 2.0 contrast ratio (1:1 to 21:1) |
| `meetsWCAGAA(against:isLargeText:)` | Check WCAG AA compliance (4.5:1 or 3:1 for large text) |
| `meetsWCAGAAA(against:isLargeText:)` | Check WCAG AAA compliance (7:1 or 4.5:1 for large text) |
| `readableTextColor` | Suggests `.black` or `.white` for best readability |

## Examples

```swift
import SwiftUtilsExtensions

// Create colors from hex strings
let primary = UIColor(hex: "#3498DB")!
let accent = UIColor(hex: "E74C3C")!
let shorthand = UIColor(hex: "#F90")!
let withAlpha = UIColor(hex: "#FF573380")!  // 50% alpha

// Convert back to hex
primary.toHex()                    // "#3498DB"
withAlpha.toHex(includeAlpha: true) // "#FF573380"

// Extract components
let (r, g, b, a) = primary.rgbaComponents
print("Red: \(r), Green: \(g), Blue: \(b), Alpha: \(a)")

let (h, s, br, _) = accent.hsbaComponents
print("Hue: \(h), Saturation: \(s), Brightness: \(br)")

// Check if a color is light or dark for adaptive UI
let backgroundColor = UIColor(hex: "#F5F5F5")!
if backgroundColor.isLight {
    label.textColor = .black
} else {
    label.textColor = .white
}
// Or use the convenience property:
label.textColor = backgroundColor.readableTextColor

// Lighten and darken for hover/pressed states
let buttonColor = UIColor(hex: "#2196F3")!
let hoverColor = buttonColor.lightened(by: 0.1)
let pressedColor = buttonColor.darkened(by: 0.15)

// Blend two colors for gradients or transitions
let start = UIColor(hex: "#FF6B6B")!
let end = UIColor(hex: "#4ECDC4")!
let midpoint = start.blended(with: end, fraction: 0.5)
let nearEnd = start.blended(with: end, fraction: 0.8)

// Adjust saturation for muted/vibrant variants
let vibrant = UIColor(hex: "#FF6B6B")!
let muted = vibrant.saturated(to: 0.3)
let fullSaturation = vibrant.saturated(to: 1.0)

// Get the complementary color
let teal = UIColor(hex: "#1ABC9C")!
let complement = teal.complementary  // opposite on the color wheel

// Set alpha
let overlay = UIColor.black.withAlpha(0.6)

// WCAG accessibility checks
let textColor = UIColor(hex: "#333333")!
let bgColor = UIColor(hex: "#FFFFFF")!
let ratio = textColor.contrastRatio(with: bgColor)
print("Contrast ratio: \(ratio):1")  // ~12.6:1

if textColor.meetsWCAGAA(against: bgColor) {
    print("Passes AA for normal text")
}

if textColor.meetsWCAGAAA(against: bgColor, isLargeText: true) {
    print("Passes AAA for large text")
}

// Real-world: validate a color palette for accessibility
let palette: [(name: String, color: UIColor)] = [
    ("Primary", UIColor(hex: "#2196F3")!),
    ("Danger", UIColor(hex: "#F44336")!),
    ("Success", UIColor(hex: "#4CAF50")!),
]
let white = UIColor.white
for (name, color) in palette {
    let passes = color.meetsWCAGAA(against: white)
    print("\(name): \(color.toHex()) — AA on white: \(passes ? "PASS" : "FAIL")")
}
```
