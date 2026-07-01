//
//  ToastPresenterTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
@testable import SwiftUtilsUIUtilities

@MainActor
final class ToastPresenterTests: XCTestCase {

    // MARK: - ToastStyle Tests

    func testStyleColors() {
        XCTAssertEqual(ToastStyle.info.backgroundColor, .systemBlue)
        XCTAssertEqual(ToastStyle.success.backgroundColor, .systemGreen)
        XCTAssertEqual(ToastStyle.warning.backgroundColor, .systemOrange)
        XCTAssertEqual(ToastStyle.error.backgroundColor, .systemRed)
        XCTAssertEqual(ToastStyle.info.foregroundColor, .white)
    }

    func testCustomStyleUsesProvidedColors() {
        let custom = ToastStyle.custom(background: .black, foreground: .yellow, icon: nil)
        XCTAssertEqual(custom.backgroundColor, .black)
        XCTAssertEqual(custom.foregroundColor, .yellow)
        XCTAssertNil(custom.icon)
    }

    func testBuiltInStylesHaveIcons() {
        XCTAssertNotNil(ToastStyle.info.icon)
        XCTAssertNotNil(ToastStyle.success.icon)
        XCTAssertNotNil(ToastStyle.warning.icon)
        XCTAssertNotNil(ToastStyle.error.icon)
    }

    // MARK: - ToastConfiguration Tests

    func testConfigurationDefaults() {
        let configuration = ToastConfiguration(message: "Hello")
        XCTAssertEqual(configuration.message, "Hello")
        XCTAssertEqual(configuration.position, .bottom)
        XCTAssertEqual(configuration.duration, 2.5, accuracy: 0.001)
        XCTAssertTrue(configuration.isSwipeToDismissEnabled)
        XCTAssertNil(configuration.onTap)
    }

    func testConfigurationCustomValues() {
        let configuration = ToastConfiguration(
            message: "Uploaded",
            style: .success,
            position: .top,
            duration: 5,
            isSwipeToDismissEnabled: false
        )
        XCTAssertEqual(configuration.position, .top)
        XCTAssertEqual(configuration.duration, 5, accuracy: 0.001)
        XCTAssertFalse(configuration.isSwipeToDismissEnabled)
    }

    // MARK: - Presenter Queueing Tests

    func testShowWithoutContainerQueuesWithoutCrashing() {
        let presenter = ToastPresenter()
        presenter.show("No container yet")
        XCTAssertEqual(presenter.queuedCount, 1)
        XCTAssertFalse(presenter.isShowingToast)
    }

    func testFirstToastPresentsImmediatelyWhenConfigured() {
        let presenter = ToastPresenter()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        presenter.configure(container: container)

        presenter.show("First")
        XCTAssertTrue(presenter.isShowingToast)
        XCTAssertEqual(presenter.queuedCount, 0)
        XCTAssertEqual(container.subviews.count, 1)
    }

    func testSecondToastIsQueuedUntilFirstDismisses() {
        let presenter = ToastPresenter()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        presenter.configure(container: container)

        presenter.show("First", duration: 0)
        presenter.show("Second", duration: 0)

        XCTAssertTrue(presenter.isShowingToast)
        XCTAssertEqual(presenter.queuedCount, 1)
        XCTAssertEqual(container.subviews.count, 1)
    }

    func testClearQueueRemovesPendingButNotActiveToast() {
        let presenter = ToastPresenter()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        presenter.configure(container: container)

        presenter.show("First", duration: 0)
        presenter.show("Second", duration: 0)
        presenter.show("Third", duration: 0)
        XCTAssertEqual(presenter.queuedCount, 2)

        presenter.clearQueue()
        XCTAssertEqual(presenter.queuedCount, 0)
        XCTAssertTrue(presenter.isShowingToast, "Clearing the queue should not dismiss the active toast")
    }

    func testDismissCurrentAdvancesToNextQueuedToast() {
        let presenter = ToastPresenter()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        presenter.configure(container: container)

        presenter.show("First", duration: 0)
        presenter.show("Second", duration: 0)

        let expectation = expectation(description: "second toast presented")
        presenter.dismissCurrent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(presenter.queuedCount, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testDismissCurrentWithNoActiveToastIsNoOp() {
        let presenter = ToastPresenter()
        let container = UIView()
        presenter.configure(container: container)
        presenter.dismissCurrent()
        XCTAssertFalse(presenter.isShowingToast)
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(ToastPresenter.shared)
    }
}
#endif
