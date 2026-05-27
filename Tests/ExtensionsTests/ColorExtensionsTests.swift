import XCTest
@testable import SwiftUtilsExtensions

final class ColorExtensionsTests: XCTestCase {

    // MARK: - Hex Init

    func testInit6DigitHex() {
        let color = UIColor(hex: "#FF5733")
        XCTAssertNotNil(color)
        let (r, g, b, a) = color!.rgbaComponents
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.34, accuracy: 0.01)
        XCTAssertEqual(b, 0.2, accuracy: 0.01)
        XCTAssertEqual(a, 1.0, accuracy: 0.01)
    }

    func testInit6DigitHexWithoutHash() {
        let color = UIColor(hex: "00FF00")
        XCTAssertNotNil(color)
        let (r, g, b, _) = color!.rgbaComponents
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(g, 1.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testInit3DigitHex() {
        let color = UIColor(hex: "#F00")
        XCTAssertNotNil(color)
        let (r, g, b, _) = color!.rgbaComponents
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testInit8DigitHexWithAlpha() {
        let color = UIColor(hex: "#FF573380")
        XCTAssertNotNil(color)
        let (_, _, _, a) = color!.rgbaComponents
        XCTAssertEqual(a, 128.0 / 255.0, accuracy: 0.01)
    }

    func testInit4DigitHex() {
        let color = UIColor(hex: "#F008")
        XCTAssertNotNil(color)
        let (r, g, b, a) = color!.rgbaComponents
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
        XCTAssertEqual(a, 0x88 / 255.0, accuracy: 0.01)
    }

    func testInitInvalidHex() {
        XCTAssertNil(UIColor(hex: "ZZZZZZ"))
        XCTAssertNil(UIColor(hex: "#GG"))
        XCTAssertNil(UIColor(hex: ""))
        XCTAssertNil(UIColor(hex: "#12345"))
    }

    // MARK: - toHex

    func testToHexRoundTrip() {
        let original = UIColor(hex: "#3498DB")!
        let hex = original.toHex()
        XCTAssertEqual(hex, "#3498DB")
    }

    func testToHexWithAlpha() {
        let color = UIColor(hex: "#FF000080")!
        let hex = color.toHex(includeAlpha: true)
        XCTAssertEqual(hex, "#FF000080")
    }

    func testToHexBlackAndWhite() {
        XCTAssertEqual(UIColor.black.toHex(), "#000000")
        XCTAssertEqual(UIColor.white.toHex(), "#FFFFFF")
    }

    // MARK: - RGBA Components

    func testRGBAComponents() {
        let color = UIColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1.0)
        let (r, g, b, a) = color.rgbaComponents
        XCTAssertEqual(r, 0.5, accuracy: 0.01)
        XCTAssertEqual(g, 0.25, accuracy: 0.01)
        XCTAssertEqual(b, 0.75, accuracy: 0.01)
        XCTAssertEqual(a, 1.0, accuracy: 0.01)
    }

    // MARK: - Luminance

    func testLuminanceWhite() {
        XCTAssertEqual(UIColor.white.luminance, 1.0, accuracy: 0.01)
    }

    func testLuminanceBlack() {
        XCTAssertEqual(UIColor.black.luminance, 0.0, accuracy: 0.01)
    }

    func testIsLight() {
        XCTAssertTrue(UIColor.white.isLight)
        XCTAssertTrue(UIColor.yellow.isLight)
        XCTAssertFalse(UIColor.black.isLight)
        XCTAssertFalse(UIColor(hex: "#333333")!.isLight)
    }

    // MARK: - Lighten / Darken

    func testLightened() {
        let base = UIColor(hex: "#808080")!
        let lighter = base.lightened(by: 0.2)
        let (_, _, bOrig, _) = base.hsbaComponents
        let (_, _, bNew, _) = lighter.hsbaComponents
        XCTAssertGreaterThan(bNew, bOrig)
    }

    func testDarkened() {
        let base = UIColor(hex: "#808080")!
        let darker = base.darkened(by: 0.2)
        let (_, _, bOrig, _) = base.hsbaComponents
        let (_, _, bNew, _) = darker.hsbaComponents
        XCTAssertLessThan(bNew, bOrig)
    }

    func testLightenedClamps() {
        let white = UIColor.white.lightened(by: 0.5)
        let (_, _, b, _) = white.hsbaComponents
        XCTAssertLessThanOrEqual(b, 1.0)
    }

    func testDarkenedClamps() {
        let black = UIColor.black.darkened(by: 0.5)
        let (_, _, b, _) = black.hsbaComponents
        XCTAssertGreaterThanOrEqual(b, 0.0)
    }

    // MARK: - Blend

    func testBlendHalfway() {
        let red = UIColor.red
        let blue = UIColor.blue
        let blended = red.blended(with: blue, fraction: 0.5)
        let (r, g, b, _) = blended.rgbaComponents
        XCTAssertEqual(r, 0.5, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.5, accuracy: 0.01)
    }

    func testBlendZeroReturnsSelf() {
        let red = UIColor.red
        let blue = UIColor.blue
        let blended = red.blended(with: blue, fraction: 0.0)
        let (r, _, b, _) = blended.rgbaComponents
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testBlendOneReturnsOther() {
        let red = UIColor.red
        let blue = UIColor.blue
        let blended = red.blended(with: blue, fraction: 1.0)
        let (r, _, b, _) = blended.rgbaComponents
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 1.0, accuracy: 0.01)
    }

    // MARK: - Complementary

    func testComplementaryRed() {
        let red = UIColor.red
        let comp = red.complementary
        let (_, _, b, _) = comp.rgbaComponents
        // Complementary of red is cyan-ish
        XCTAssertGreaterThan(b, 0.5)
    }

    // MARK: - Contrast Ratio

    func testContrastRatioBlackWhite() {
        let ratio = UIColor.black.contrastRatio(with: .white)
        XCTAssertEqual(ratio, 21.0, accuracy: 0.1)
    }

    func testContrastRatioSameColor() {
        let ratio = UIColor.red.contrastRatio(with: .red)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.01)
    }

    // MARK: - WCAG

    func testMeetsWCAGAA() {
        // Black on white should always pass
        XCTAssertTrue(UIColor.black.meetsWCAGAA(against: .white))
        XCTAssertTrue(UIColor.black.meetsWCAGAA(against: .white, isLargeText: true))
    }

    func testFailsWCAGAA() {
        // Light gray on white fails
        let lightGray = UIColor(hex: "#CCCCCC")!
        XCTAssertFalse(lightGray.meetsWCAGAA(against: .white))
    }

    func testMeetsWCAGAAA() {
        XCTAssertTrue(UIColor.black.meetsWCAGAAA(against: .white))
    }

    // MARK: - Readable Text Color

    func testReadableTextColorOnWhite() {
        XCTAssertEqual(UIColor.white.readableTextColor, .black)
    }

    func testReadableTextColorOnBlack() {
        XCTAssertEqual(UIColor.black.readableTextColor, .white)
    }

    func testReadableTextColorOnYellow() {
        // Yellow is light, so text should be black
        XCTAssertEqual(UIColor.yellow.readableTextColor, .black)
    }

    // MARK: - Saturation

    func testSaturated() {
        let color = UIColor(hex: "#FF6666")!
        let saturated = color.saturated(to: 1.0)
        let (_, s, _, _) = saturated.hsbaComponents
        XCTAssertEqual(s, 1.0, accuracy: 0.01)
    }

    func testDesaturated() {
        let color = UIColor(hex: "#FF6666")!
        let desaturated = color.saturated(to: 0.0)
        let (_, s, _, _) = desaturated.hsbaComponents
        XCTAssertEqual(s, 0.0, accuracy: 0.01)
    }

    // MARK: - withAlpha

    func testWithAlpha() {
        let color = UIColor.red.withAlpha(0.5)
        let (_, _, _, a) = color.rgbaComponents
        XCTAssertEqual(a, 0.5, accuracy: 0.01)
    }
}
