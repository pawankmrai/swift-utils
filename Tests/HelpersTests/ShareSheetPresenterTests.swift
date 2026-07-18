//
//  ShareSheetPresenterTests.swift
//  SwiftUtils
//

import XCTest
@testable import SwiftUtilsHelpers

final class ShareSheetPresenterTests: XCTestCase {

    /// A `UIViewController` that records what would have been presented
    /// instead of actually performing a presentation, so tests can run
    /// without a real window/scene.
    final class PresentationSpyViewController: UIViewController {
        private(set) var presentedController: UIViewController?
        private(set) var presentCallCount = 0

        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
            presentCallCount += 1
            presentedController = viewControllerToPresent
            completion?()
        }
    }

    var spy: PresentationSpyViewController!

    override func setUp() {
        super.setUp()
        spy = PresentationSpyViewController()
        // Force the view to load so `.view` (used for popover fallback anchoring) is available.
        _ = spy.view
    }

    override func tearDown() {
        spy = nil
        super.tearDown()
    }

    // MARK: - Empty Items

    func testPresentWithEmptyItemsDoesNotPresentAnything() {
        ShareSheetPresenter.present([], from: spy)
        XCTAssertEqual(spy.presentCallCount, 0)
        XCTAssertNil(spy.presentedController)
    }

    func testPresentWithEmptyItemsDoesNotInvokeCompletion() {
        var completionCalled = false
        ShareSheetPresenter.present([], from: spy) { _ in completionCalled = true }
        XCTAssertFalse(completionCalled)
    }

    // MARK: - Basic Presentation

    func testPresentWithTextItemPresentsActivityController() {
        ShareSheetPresenter.present([.text("Hello, world!")], from: spy)
        XCTAssertEqual(spy.presentCallCount, 1)
        XCTAssertTrue(spy.presentedController is UIActivityViewController)
    }

    func testPresentWithMultipleItemsPresentsOnce() {
        let url = URL(string: "https://example.com")!
        ShareSheetPresenter.present([.text("Check this out"), .url(url)], from: spy)
        XCTAssertEqual(spy.presentCallCount, 1)
    }

    func testPresentTextConvenienceMethodPresents() {
        ShareSheetPresenter.presentText("Some text", from: spy)
        XCTAssertEqual(spy.presentCallCount, 1)
    }

    func testPresentURLConvenienceMethodPresents() {
        ShareSheetPresenter.presentURL(URL(string: "https://example.com")!, from: spy)
        XCTAssertEqual(spy.presentCallCount, 1)
    }

    func testPresentImageConvenienceMethodPresents() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        ShareSheetPresenter.presentImage(image, from: spy)
        XCTAssertEqual(spy.presentCallCount, 1)
    }

    // MARK: - Excluded Activity Types

    func testExcludedActivityTypesArePassedThrough() throws {
        ShareSheetPresenter.present(
            [.text("hi")],
            from: spy,
            excludedActivityTypes: [.assignToContact, .print]
        )
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)
        XCTAssertEqual(controller.excludedActivityTypes, [.assignToContact, .print])
    }

    func testDefaultExcludedActivityTypesIsEmpty() throws {
        ShareSheetPresenter.present([.text("hi")], from: spy)
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)
        XCTAssertEqual(controller.excludedActivityTypes, [])
    }

    // MARK: - iPad Popover Anchoring

    func testSourceViewIsAssignedToPopoverPresentationController() throws {
        let button = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        spy.view.addSubview(button)

        ShareSheetPresenter.present([.text("hi")], from: spy, sourceView: button)
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)

        XCTAssertEqual(controller.popoverPresentationController?.sourceView, button)
    }

    func testMissingSourceViewFallsBackToPresentingViewWithoutCrashing() throws {
        ShareSheetPresenter.present([.text("hi")], from: spy)
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)

        XCTAssertEqual(controller.popoverPresentationController?.sourceView, spy.view)
    }

    func testBarButtonItemAnchoringAssignsBarButtonItem() throws {
        let item = UIBarButtonItem(barButtonSystemItem: .action, target: nil, action: nil)
        ShareSheetPresenter.present([.text("hi")], from: spy, barButtonItem: item)
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)

        XCTAssertEqual(controller.popoverPresentationController?.barButtonItem, item)
    }

    // MARK: - Completion Handling

    func testCompletionReceivesCompletedFlagAndActivityType() throws {
        ShareSheetPresenter.present([.text("hi")], from: spy)
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)

        let expectation = expectation(description: "completion handler invoked")
        var receivedResult: ShareSheetPresenter.Result?

        ShareSheetPresenter.present([.text("hi")], from: spy) { result in
            receivedResult = result
            expectation.fulfill()
        }
        guard let latest = spy.presentedController as? UIActivityViewController else {
            return XCTFail("expected an activity controller")
        }
        latest.completionWithItemsHandler?(.copyToPasteboard, true, nil, nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedResult?.completed, true)
        XCTAssertEqual(receivedResult?.activityType, .copyToPasteboard)
        _ = controller
    }

    func testCompletionReportsCancellation() throws {
        let expectation = expectation(description: "completion handler invoked")
        var receivedResult: ShareSheetPresenter.Result?

        ShareSheetPresenter.present([.text("hi")], from: spy) { result in
            receivedResult = result
            expectation.fulfill()
        }
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)
        controller.completionWithItemsHandler?(nil, false, nil, nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedResult?.completed, false)
        XCTAssertNil(receivedResult?.activityType)
    }

    func testCompletionReportsError() throws {
        struct SampleError: Error {}
        let expectation = expectation(description: "completion handler invoked")
        var receivedResult: ShareSheetPresenter.Result?

        ShareSheetPresenter.present([.text("hi")], from: spy) { result in
            receivedResult = result
            expectation.fulfill()
        }
        let controller = try XCTUnwrap(spy.presentedController as? UIActivityViewController)
        controller.completionWithItemsHandler?(.mail, false, nil, SampleError())

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(receivedResult?.error)
    }
}
