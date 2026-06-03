import XCTest
@testable import SwiftUtilsUIUtilities

final class AnimationUtilitiesTests: XCTestCase {

    // MARK: - AnimationConfig Builder Tests

    func testDefaultConfig() {
        // Verify that AnimationConfig can be created with defaults
        let config = AnimationConfig()
        // Should not crash; config uses sensible defaults
        XCTAssertNotNil(config)
    }

    func testChainableSetters() {
        let config = AnimationConfig()
            .duration(0.5)
            .delay(0.1)
            .springDamping(0.7)
            .initialVelocity(0.3)
            .options(.allowUserInteraction)
            .curve(.easeOut)

        // Verify chaining returns a new config (value type)
        XCTAssertNotNil(config)
    }

    func testPresetsExist() {
        XCTAssertNotNil(AnimationConfig.quickFade)
        XCTAssertNotNil(AnimationConfig.spring)
        XCTAssertNotNil(AnimationConfig.bouncy)
        XCTAssertNotNil(AnimationConfig.smooth)
    }

    // MARK: - SlideEdge Tests

    func testSlideEdgeTop() {
        let (dx, dy) = SlideEdge.top.translationComponents(offset: 100)
        XCTAssertEqual(dx, 0)
        XCTAssertEqual(dy, -100)
    }

    func testSlideEdgeBottom() {
        let (dx, dy) = SlideEdge.bottom.translationComponents(offset: 50)
        XCTAssertEqual(dx, 0)
        XCTAssertEqual(dy, 50)
    }

    func testSlideEdgeLeading() {
        let (dx, dy) = SlideEdge.leading.translationComponents(offset: 80)
        XCTAssertEqual(dx, -80)
        XCTAssertEqual(dy, 0)
    }

    func testSlideEdgeTrailing() {
        let (dx, dy) = SlideEdge.trailing.translationComponents(offset: 60)
        XCTAssertEqual(dx, 60)
        XCTAssertEqual(dy, 0)
    }

    // MARK: - AnimationSequence Tests

    func testEmptySequenceCallsCompletion() {
        let expectation = expectation(description: "completion called")
        AnimationSequence().run {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testSequenceStepChaining() {
        let sequence = AnimationSequence()
            .step(duration: 0.1) { }
            .step(duration: 0.1) { }
            .step(config: .quickFade) { }

        // Verify it doesn't crash and returns self
        XCTAssertNotNil(sequence)
    }

    func testSequenceRunsStepsInOrder() {
        let expectation = expectation(description: "sequence completes")
        var order: [Int] = []

        AnimationSequence()
            .step(duration: 0.05) { order.append(1) }
            .step(duration: 0.05) { order.append(2) }
            .step(duration: 0.05) { order.append(3) }
            .run {
                XCTAssertEqual(order, [1, 2, 3])
                expectation.fulfill()
            }

        wait(for: [expectation], timeout: 2.0)
    }
}
