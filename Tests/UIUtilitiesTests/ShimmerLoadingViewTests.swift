//
//  ShimmerLoadingViewTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
@testable import SwiftUtilsUIUtilities

final class ShimmerLoadingViewTests: XCTestCase {

    // MARK: - Configuration

    func testDefaultConfigurationValues() {
        let config = ShimmerConfiguration.default
        XCTAssertEqual(config.duration, 1.2, accuracy: 0.001)
        XCTAssertEqual(config.pauseBetweenPasses, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.bandWidth, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.direction, .leftToRight)
    }

    func testCustomConfigurationRetainsValues() {
        let config = ShimmerConfiguration(
            baseColor: .black,
            highlightColor: .white,
            duration: 2.0,
            pauseBetweenPasses: 0.5,
            direction: .topToBottom,
            bandWidth: 0.5
        )
        XCTAssertEqual(config.duration, 2.0, accuracy: 0.001)
        XCTAssertEqual(config.pauseBetweenPasses, 0.5, accuracy: 0.001)
        XCTAssertEqual(config.bandWidth, 0.5, accuracy: 0.001)
        XCTAssertEqual(config.direction, .topToBottom)
        XCTAssertEqual(config.baseColor, .black)
        XCTAssertEqual(config.highlightColor, .white)
    }

    // MARK: - Lifecycle

    func testInitialStateIsNotShimmering() {
        let view = ShimmerLoadingView()
        XCTAssertFalse(view.isShimmering)
    }

    func testStartShimmeringSetsFlagAndAddsAnimation() {
        let view = ShimmerLoadingView()
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        view.startShimmering()

        XCTAssertTrue(view.isShimmering)
        XCTAssertNotNil(view.layer.sublayers?.first?.animation(forKey: "shimmer"))
    }

    func testStopShimmeringClearsFlagAndRemovesAnimation() {
        let view = ShimmerLoadingView()
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        view.startShimmering()
        view.stopShimmering()

        XCTAssertFalse(view.isShimmering)
        XCTAssertNil(view.layer.sublayers?.first?.animation(forKey: "shimmer"))
    }

    func testChangingConfigurationWhileShimmeringRestartsAnimation() {
        let view = ShimmerLoadingView()
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        view.startShimmering()
        XCTAssertTrue(view.isShimmering)

        view.configuration = ShimmerConfiguration(direction: .rightToLeft)
        XCTAssertTrue(view.isShimmering)
        XCTAssertNotNil(view.layer.sublayers?.first?.animation(forKey: "shimmer"))
    }

    func testChangingConfigurationWhileNotShimmeringDoesNotStart() {
        let view = ShimmerLoadingView()
        view.configuration = ShimmerConfiguration(direction: .bottomToTop)
        XCTAssertFalse(view.isShimmering)
    }

    func testLayoutSubviewsExpandsGradientLayerBeyondBounds() {
        let view = ShimmerLoadingView()
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
        view.layoutIfNeeded()

        guard let gradientLayer = view.layer.sublayers?.first else {
            return XCTFail("Expected a gradient sublayer")
        }
        XCTAssertGreaterThan(gradientLayer.frame.width, view.bounds.width)
        XCTAssertGreaterThan(gradientLayer.frame.height, view.bounds.height)
    }
}
#endif
