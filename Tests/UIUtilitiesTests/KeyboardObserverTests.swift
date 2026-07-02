//
//  KeyboardObserverTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
import Combine
@testable import SwiftUtilsUIUtilities

@MainActor
final class KeyboardObserverTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultsBeforeAnyNotification() {
        let observer = KeyboardObserver()
        XCTAssertEqual(observer.keyboardHeight, 0)
        XCTAssertFalse(observer.isVisible)
        XCTAssertEqual(observer.animationDuration, 0.25, accuracy: 0.0001)
    }

    // MARK: - Show

    func testWillShowUpdatesHeightAndVisibility() {
        let observer = KeyboardObserver()
        let expectation = expectation(description: "height updated")

        observer.$keyboardHeight
            .dropFirst()
            .sink { height in
                XCTAssertGreaterThan(height, 0)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        postKeyboardNotification(.keyboardWillShow, height: 300)
        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(observer.isVisible)
        XCTAssertEqual(observer.keyboardHeight, 300, accuracy: 0.5)
    }

    func testWillShowUsesNotificationAnimationDuration() {
        let observer = KeyboardObserver()
        let expectation = expectation(description: "duration updated")

        observer.$animationDuration
            .dropFirst()
            .sink { duration in
                XCTAssertEqual(duration, 0.35, accuracy: 0.0001)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        postKeyboardNotification(.keyboardWillShow, height: 250, duration: 0.35)
        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Hide

    func testWillHideResetsHeightAndVisibility() {
        let observer = KeyboardObserver()

        let shown = expectation(description: "shown")
        observer.$isVisible.dropFirst().sink { visible in
            if visible { shown.fulfill() }
        }.store(in: &cancellables)
        postKeyboardNotification(.keyboardWillShow, height: 300)
        wait(for: [shown], timeout: 1)

        let hidden = expectation(description: "hidden")
        observer.$isVisible.dropFirst().sink { visible in
            if !visible { hidden.fulfill() }
        }.store(in: &cancellables)
        postKeyboardNotification(.keyboardWillHide, height: 0)
        wait(for: [hidden], timeout: 1)

        XCTAssertEqual(observer.keyboardHeight, 0)
        XCTAssertFalse(observer.isVisible)
    }

    // MARK: - Independence

    func testIndependentObserversDoNotShareState() {
        let a = KeyboardObserver()
        let b = KeyboardObserver()

        let expectation = expectation(description: "only a updates")
        var bChanged = false

        b.$keyboardHeight.dropFirst().sink { _ in bChanged = true }.store(in: &cancellables)
        a.$keyboardHeight.dropFirst().sink { _ in expectation.fulfill() }.store(in: &cancellables)

        postKeyboardNotification(.keyboardWillShow, height: 280)
        wait(for: [expectation], timeout: 1)

        XCTAssertTrue(bChanged, "Both observers listen to the same system notifications")
        XCTAssertEqual(a.keyboardHeight, b.keyboardHeight, accuracy: 0.5)
    }

    // MARK: - heightStream

    func testHeightStreamYieldsUpdates() async {
        let observer = KeyboardObserver()
        let stream = observer.heightStream

        let task = Task { () -> CGFloat? in
            for await height in stream where height > 0 {
                return height
            }
            return nil
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        postKeyboardNotification(.keyboardWillShow, height: 260)

        let result = await task.value
        XCTAssertEqual(result ?? 0, 260, accuracy: 0.5)
    }

    // MARK: - Helpers

    private enum KeyboardEvent {
        case keyboardWillShow
        case keyboardWillHide

        var notificationName: Notification.Name {
            switch self {
            case .keyboardWillShow: return UIResponder.keyboardWillShowNotification
            case .keyboardWillHide: return UIResponder.keyboardWillHideNotification
            }
        }
    }

    private func postKeyboardNotification(_ event: KeyboardEvent, height: CGFloat, duration: TimeInterval = 0.25) {
        let screenHeight = UIScreen.main.bounds.height
        let frame = CGRect(
            x: 0,
            y: height > 0 ? screenHeight - height : screenHeight,
            width: UIScreen.main.bounds.width,
            height: max(height, 1)
        )
        let userInfo: [AnyHashable: Any] = [
            UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
            UIResponder.keyboardAnimationDurationUserInfoKey: duration,
            UIResponder.keyboardAnimationCurveUserInfoKey: UInt(7)
        ]
        NotificationCenter.default.post(name: event.notificationName, object: nil, userInfo: userInfo)
    }
}
#endif
