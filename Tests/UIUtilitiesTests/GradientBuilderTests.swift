//
//  GradientBuilderTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
@testable import SwiftUtilsUIUtilities

final class GradientBuilderTests: XCTestCase {

    // MARK: - GradientStop Tests

    func testGradientStopClampsLocation() {
        let underflow = GradientStop(color: .red, location: -0.5)
        XCTAssertEqual(underflow.location, 0, accuracy: 0.001)

        let overflow = GradientStop(color: .red, location: 1.5)
        XCTAssertEqual(overflow.location, 1, accuracy: 0.001)

        let valid = GradientStop(color: .red, location: 0.5)
        XCTAssertEqual(valid.location, 0.5, accuracy: 0.001)
    }

    // MARK: - GradientDirection Tests

    func testDirectionPoints() {
        let topToBottom = GradientDirection.topToBottom
        XCTAssertEqual(topToBottom.startPoint, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(topToBottom.endPoint, CGPoint(x: 0.5, y: 1))

        let leftToRight = GradientDirection.leftToRight
        XCTAssertEqual(leftToRight.startPoint, CGPoint(x: 0, y: 0.5))
        XCTAssertEqual(leftToRight.endPoint, CGPoint(x: 1, y: 0.5))

        let diagonal = GradientDirection.topLeftToBottomRight
        XCTAssertEqual(diagonal.startPoint, CGPoint(x: 0, y: 0))
        XCTAssertEqual(diagonal.endPoint, CGPoint(x: 1, y: 1))
    }

    func testCustomDirection() {
        let start = CGPoint(x: 0.2, y: 0.3)
        let end = CGPoint(x: 0.8, y: 0.9)
        let custom = GradientDirection.custom(start: start, end: end)
        XCTAssertEqual(custom.startPoint, start)
        XCTAssertEqual(custom.endPoint, end)
    }

    func testAllDirectionsHaveValidPoints() {
        let directions: [GradientDirection] = [
            .topToBottom, .bottomToTop, .leftToRight, .rightToLeft,
            .topLeftToBottomRight, .topRightToBottomLeft,
            .bottomLeftToTopRight, .bottomRightToTopLeft
        ]
        for direction in directions {
            let sp = direction.startPoint
            let ep = direction.endPoint
            XCTAssert(sp.x >= 0 && sp.x <= 1, "startPoint.x out of range for \(direction)")
            XCTAssert(sp.y >= 0 && sp.y <= 1, "startPoint.y out of range for \(direction)")
            XCTAssert(ep.x >= 0 && ep.x <= 1, "endPoint.x out of range for \(direction)")
            XCTAssert(ep.y >= 0 && ep.y <= 1, "endPoint.y out of range for \(direction)")
        }
    }

    // MARK: - GradientBuilder Tests

    func testBuildLinearGradient() {
        let layer = GradientBuilder()
            .add(color: .red, at: 0)
            .add(color: .blue, at: 1)
            .direction(.leftToRight)
            .build(in: CGRect(x: 0, y: 0, width: 200, height: 100))

        XCTAssertEqual(layer.frame.width, 200)
        XCTAssertEqual(layer.frame.height, 100)
        XCTAssertEqual(layer.colors?.count, 2)
        XCTAssertEqual(layer.locations?.count, 2)
        XCTAssertEqual(layer.type, .axial)
        XCTAssertEqual(layer.startPoint, CGPoint(x: 0, y: 0.5))
        XCTAssertEqual(layer.endPoint, CGPoint(x: 1, y: 0.5))
    }

    func testBuildRadialGradient() {
        let center = CGPoint(x: 0.5, y: 0.5)
        let layer = GradientBuilder()
            .add(color: .white, at: 0)
            .add(color: .black, at: 1)
            .radial(center: center, radius: 0.5)
            .build(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(layer.type, .radial)
        XCTAssertEqual(layer.startPoint, center)
    }

    func testCornerRadius() {
        let layer = GradientBuilder()
            .add(color: .red, at: 0)
            .add(color: .blue, at: 1)
            .cornerRadius(16)
            .build(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(layer.cornerRadius, 16)
    }

    func testStopsAreSortedByLocation() {
        let layer = GradientBuilder()
            .add(color: .blue, at: 1.0)
            .add(color: .red, at: 0.0)
            .add(color: .green, at: 0.5)
            .build(in: CGRect(x: 0, y: 0, width: 100, height: 100))

        let locations = layer.locations?.map { $0.doubleValue } ?? []
        XCTAssertEqual(locations, [0.0, 0.5, 1.0])
    }

    func testRenderImageReturnsNonNil() {
        let image = GradientBuilder()
            .add(color: .red, at: 0)
            .add(color: .blue, at: 1)
            .renderImage(size: CGSize(width: 50, height: 50))

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size.width, 50)
        XCTAssertEqual(image?.size.height, 50)
    }

    func testChainingReturnsSelf() {
        let builder = GradientBuilder()
        let result = builder
            .add(color: .red, at: 0)
            .add(color: .blue, at: 1)
            .direction(.topToBottom)
            .cornerRadius(8)

        // Verify all chained methods return the same builder instance
        XCTAssert(result === builder)
    }

    // MARK: - Preset Tests

    func testPresetSunset() {
        let layer = GradientBuilder.sunset.build(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(layer.colors?.count, 3)
        XCTAssertEqual(layer.type, .axial)
    }

    func testPresetOcean() {
        let layer = GradientBuilder.ocean.build(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(layer.colors?.count, 2)
        XCTAssertEqual(layer.startPoint, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(layer.endPoint, CGPoint(x: 0.5, y: 1))
    }

    func testPresetForest() {
        let layer = GradientBuilder.forest.build(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(layer.colors?.count, 2)
    }

    func testPresetNightSky() {
        let layer = GradientBuilder.nightSky.build(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(layer.colors?.count, 3)
    }
}
#endif
