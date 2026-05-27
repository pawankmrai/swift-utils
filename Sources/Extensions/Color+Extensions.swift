import UIKit

// MARK: - Hex Initialization

public extension UIColor {

    /// Creates a color from a hex string (e.g. `"#FF5733"`, `"FF5733"`, `"#F53"`).
    ///
    /// Supports 3-digit (RGB), 4-digit (RGBA), 6-digit (RRGGBB), and 8-digit (RRGGBBAA) hex strings.
    /// The leading `#` is optional.
    ///
    /// - Parameter hex: A hex color string.
    convenience init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        let expanded: String
        switch cleaned.count {
        case 3: // RGB → RRGGBB
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        case 4: // RGBA → RRGGBBAA
            expanded = cleaned.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = cleaned
        default:
            return nil
        }

        var hexValue: UInt64 = 0
        guard Scanner(string: expanded).scanHexInt64(&hexValue) else { return nil }

        if expanded.count == 8 {
            self.init(
                red: CGFloat((hexValue >> 24) & 0xFF) / 255.0,
                green: CGFloat((hexValue >> 16) & 0xFF) / 255.0,
                blue: CGFloat((hexValue >> 8) & 0xFF) / 255.0,
                alpha: CGFloat(hexValue & 0xFF) / 255.0
            )
        } else {
            self.init(
                red: CGFloat((hexValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((hexValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hexValue & 0xFF) / 255.0,
                alpha: 1.0
            )
        }
    }

    /// Returns the hex string representation of the color (e.g. `"#FF5733"`).
    ///
    /// - Parameter includeAlpha: Whether to include the alpha component. Defaults to `false`.
    /// - Returns: A hex string such as `"#RRGGBB"` or `"#RRGGBBAA"`.
    func toHex(includeAlpha: Bool = false) -> String {
        let (r, g, b, a) = rgbaComponents
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        if includeAlpha {
            let ai = Int(round(a * 255))
            return String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
        }
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

// MARK: - RGBA Components

public extension UIColor {

    /// Extracts the RGBA components as a tuple of `CGFloat` values in the 0…1 range.
    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// Extracts the HSBA components as a tuple of `CGFloat` values.
    var hsbaComponents: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b, a)
    }

    /// The perceived luminance of the color (0 = darkest, 1 = lightest).
    ///
    /// Uses the W3C relative luminance formula from WCAG 2.0.
    var luminance: CGFloat {
        let (r, g, b, _) = rgbaComponents
        func linearize(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// Returns `true` if the color is considered light (luminance > 0.5).
    var isLight: Bool { luminance > 0.5 }
}

// MARK: - Color Manipulation

public extension UIColor {

    /// Returns a lighter version of the color.
    ///
    /// - Parameter amount: How much to lighten, from 0.0 (no change) to 1.0 (white). Defaults to `0.2`.
    func lightened(by amount: CGFloat = 0.2) -> UIColor {
        adjustBrightness(by: abs(amount))
    }

    /// Returns a darker version of the color.
    ///
    /// - Parameter amount: How much to darken, from 0.0 (no change) to 1.0 (black). Defaults to `0.2`.
    func darkened(by amount: CGFloat = 0.2) -> UIColor {
        adjustBrightness(by: -abs(amount))
    }

    /// Returns the color with the specified alpha value.
    ///
    /// - Parameter alpha: The new alpha value (0…1).
    func withAlpha(_ alpha: CGFloat) -> UIColor {
        withAlphaComponent(alpha)
    }

    /// Returns a new color adjusted toward the given saturation.
    ///
    /// - Parameter amount: The new saturation value (0…1).
    func saturated(to amount: CGFloat) -> UIColor {
        let (h, _, b, a) = hsbaComponents
        return UIColor(hue: h, saturation: min(max(amount, 0), 1), brightness: b, alpha: a)
    }

    /// Blends this color with another by the given fraction.
    ///
    /// - Parameters:
    ///   - other: The color to blend toward.
    ///   - fraction: Blend amount from 0.0 (all self) to 1.0 (all other). Defaults to `0.5`.
    func blended(with other: UIColor, fraction: CGFloat = 0.5) -> UIColor {
        let t = min(max(fraction, 0), 1)
        let (r1, g1, b1, a1) = rgbaComponents
        let (r2, g2, b2, a2) = other.rgbaComponents
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }

    /// Returns the complementary color (opposite on the color wheel).
    var complementary: UIColor {
        let (h, s, b, a) = hsbaComponents
        return UIColor(hue: (h + 0.5).truncatingRemainder(dividingBy: 1.0), saturation: s, brightness: b, alpha: a)
    }

    // MARK: Private

    private func adjustBrightness(by amount: CGFloat) -> UIColor {
        let (h, s, b, a) = hsbaComponents
        return UIColor(
            hue: h,
            saturation: s,
            brightness: min(max(b + amount, 0), 1),
            alpha: a
        )
    }
}

// MARK: - Contrast & Accessibility

public extension UIColor {

    /// Computes the WCAG 2.0 contrast ratio between this color and another.
    ///
    /// The ratio ranges from 1:1 (identical) to 21:1 (black vs. white).
    ///
    /// - Parameter other: The color to compare against.
    /// - Returns: The contrast ratio as a `CGFloat`.
    func contrastRatio(with other: UIColor) -> CGFloat {
        let l1 = max(luminance, other.luminance)
        let l2 = min(luminance, other.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    /// Checks if the contrast ratio with another color meets WCAG AA requirements.
    ///
    /// - Parameters:
    ///   - other: The color to compare against.
    ///   - isLargeText: Whether the text is large (>= 18pt or >= 14pt bold). Defaults to `false`.
    /// - Returns: `true` if the contrast ratio meets the AA threshold.
    func meetsWCAGAA(against other: UIColor, isLargeText: Bool = false) -> Bool {
        contrastRatio(with: other) >= (isLargeText ? 3.0 : 4.5)
    }

    /// Checks if the contrast ratio with another color meets WCAG AAA requirements.
    ///
    /// - Parameters:
    ///   - other: The color to compare against.
    ///   - isLargeText: Whether the text is large (>= 18pt or >= 14pt bold). Defaults to `false`.
    /// - Returns: `true` if the contrast ratio meets the AAA threshold.
    func meetsWCAGAAA(against other: UIColor, isLargeText: Bool = false) -> Bool {
        contrastRatio(with: other) >= (isLargeText ? 4.5 : 7.0)
    }

    /// Suggests black or white as the best readable text color for this background.
    var readableTextColor: UIColor {
        isLight ? .black : .white
    }
}
