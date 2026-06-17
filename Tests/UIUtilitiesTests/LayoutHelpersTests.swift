//
//  LayoutHelpersTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
@testable import SwiftUtilsUIUtilities

final class LayoutHelpersTests: XCTestCase {

    // MARK: - LayoutEdges Tests

    func testLayoutEdgesComposition() {
        XCTAssertEqual(LayoutEdges.all, [.top, .leading, .trailing, .bottom])
        XCTAssertEqual(LayoutEdges.horizontal, [.leading, .trailing])
        XCTAssertEqual(LayoutEdges.vertical, [.top, .bottom])
        XCTAssertTrue(LayoutEdges.all.contains(.top))
        XCTAssertFalse(LayoutEdges.horizontal.contains(.top))
    }

    // MARK: - NSDirectionalEdgeInsets Convenience Tests

    func testInsetsAll() {
        let insets = NSDirectionalEdgeInsets.all(8)
        XCTAssertEqual(insets.top, 8)
        XCTAssertEqual(insets.leading, 8)
        XCTAssertEqual(insets.trailing, 8)
        XCTAssertEqual(insets.bottom, 8)
    }

    func testInsetsSymmetric() {
        let insets = NSDirectionalEdgeInsets.symmetric(horizontal: 16, vertical: 4)
        XCTAssertEqual(insets.leading, 16)
        XCTAssertEqual(insets.trailing, 16)
        XCTAssertEqual(insets.top, 4)
        XCTAssertEqual(insets.bottom, 4)
    }

    // MARK: - LayoutAnchorBuilder Tests

    func testPinAllEdgesProducesFourConstraints() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.pin(.all, to: container, insets: .all(8)).constraints()
        XCTAssertEqual(constraints.count, 4)
        XCTAssertFalse(child.translatesAutoresizingMaskIntoConstraints)
    }

    func testPinSubsetOfEdges() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.pin(.horizontal, to: container).constraints()
        XCTAssertEqual(constraints.count, 2)
    }

    func testPinInsetConstantsAppliedCorrectly() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.pin(.top, to: container, insets: .all(12)).constraints()
        XCTAssertEqual(constraints.first?.constant, 12)
    }

    func testCenterProducesTwoConstraints() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.center(in: container, offset: CGPoint(x: 5, y: -5)).constraints()
        XCTAssertEqual(constraints.count, 2)
        XCTAssertEqual(constraints[0].constant, 5)
        XCTAssertEqual(constraints[1].constant, -5)
    }

    func testSizeSetsFixedConstants() {
        let view = UIView()
        let constraints = view.layout.size(width: 100, height: 44).constraints()
        XCTAssertEqual(constraints.count, 2)
        XCTAssertEqual(constraints[0].constant, 100)
        XCTAssertEqual(constraints[1].constant, 44)
    }

    func testSizeWithOnlyOneDimension() {
        let view = UIView()
        let constraints = view.layout.size(height: 44).constraints()
        XCTAssertEqual(constraints.count, 1)
        XCTAssertEqual(constraints[0].firstAttribute, .height)
    }

    func testAspectRatioUsesMultiplier() {
        let view = UIView()
        let constraints = view.layout.aspectRatio(16.0 / 9.0).constraints()
        XCTAssertEqual(constraints.count, 1)
        XCTAssertEqual(constraints[0].multiplier, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testMatchDimensionWithMultiplier() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.match(.width, of: container, multiplier: 0.5).constraints()
        XCTAssertEqual(constraints.count, 1)
        XCTAssertEqual(constraints[0].multiplier, 0.5, accuracy: 0.0001)
    }

    func testPriorityAppliedToAllConstraintsInChain() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout
            .pin(.all, to: container)
            .priority(.defaultHigh)
            .constraints()

        XCTAssertTrue(constraints.allSatisfy { $0.priority == .defaultHigh })
    }

    func testActivateActuallyActivatesConstraints() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.pin(.all, to: container).activate()
        XCTAssertTrue(constraints.allSatisfy { $0.isActive })
    }

    // MARK: - UIView Convenience Tests

    func testPinToSuperviewReturnsNilWithoutSuperview() {
        let orphan = UIView()
        XCTAssertNil(orphan.pinToSuperview())
    }

    func testPinToSuperviewActivatesConstraints() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.pinToSuperview(insets: .all(4))
        XCTAssertEqual(constraints?.count, 4)
        XCTAssertTrue(constraints?.allSatisfy { $0.isActive } ?? false)
    }

    func testCenterInSuperviewReturnsNilWithoutSuperview() {
        let orphan = UIView()
        XCTAssertNil(orphan.centerInSuperview())
    }

    func testCenterInSuperviewActivatesConstraints() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.centerInSuperview()
        XCTAssertEqual(constraints?.count, 2)
    }

    // MARK: - LayoutAnchorProviding Tests

    func testUILayoutGuideConformsToProtocol() {
        let container = UIView()
        let guide = UILayoutGuide()
        container.addLayoutGuide(guide)
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.pin(.all, to: guide).constraints()
        XCTAssertEqual(constraints.count, 4)
    }

    func testSafeAreaLayoutGuideWorksAsAnchorProvider() {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        let constraints = child.layout.pin(.top, to: container.safeAreaLayoutGuide).constraints()
        XCTAssertEqual(constraints.count, 1)
    }
}
#endif
