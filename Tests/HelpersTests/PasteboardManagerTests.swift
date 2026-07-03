//
//  PasteboardManagerTests.swift
//  SwiftUtils
//

import XCTest
@testable import SwiftUtilsHelpers

final class PasteboardManagerTests: XCTestCase {

    var manager: PasteboardManager!

    override func setUp() {
        super.setUp()
        // Use a uniquely named pasteboard per test run so tests never touch
        // the real system clipboard and can't interfere with each other.
        let name = UIPasteboard.Name("com.swiftutils.tests.\(UUID().uuidString)")
        manager = PasteboardManager(named: name, create: true)
        manager.clear()
    }

    override func tearDown() {
        manager.clear()
        manager = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testSharedInstanceExists() {
        XCTAssertNotNil(PasteboardManager.shared)
    }

    func testSharedInstanceIsSingleton() {
        let a = PasteboardManager.shared
        let b = PasteboardManager.shared
        XCTAssertTrue(a === b)
    }

    func testDefaultInitUsesGeneralPasteboard() {
        let m = PasteboardManager()
        XCTAssertNotNil(m)
    }

    // MARK: - String Copy/Paste

    func testCopyAndReadString() {
        manager.copy("hello world")
        XCTAssertEqual(manager.string(), "hello world")
    }

    func testHasStringsReflectsContent() {
        XCTAssertFalse(manager.hasStrings)
        manager.copy("some text")
        XCTAssertTrue(manager.hasStrings)
    }

    func testStringIsNilWhenEmpty() {
        XCTAssertNil(manager.string())
    }

    // MARK: - URL Copy/Paste

    func testCopyAndReadURL() {
        let url = URL(string: "https://example.com/path?query=1")!
        manager.copy(url)
        XCTAssertEqual(manager.url(), url)
    }

    func testHasURLsReflectsContent() {
        XCTAssertFalse(manager.hasURLs)
        manager.copy(URL(string: "https://example.com")!)
        XCTAssertTrue(manager.hasURLs)
    }

    func testURLFallsBackToParsingPlainTextString() {
        manager.copy("https://fallback.example.com")
        XCTAssertEqual(manager.url(), URL(string: "https://fallback.example.com"))
    }

    func testURLReturnsNilForNonURLString() {
        manager.copy("not a url at all, just words")
        XCTAssertNil(manager.url())
    }

    // MARK: - Image Copy/Paste

    func testCopyAndReadImage() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        manager.copy(image)
        XCTAssertTrue(manager.hasImages)
        XCTAssertNotNil(manager.image())
    }

    // MARK: - Color Copy/Paste

    func testCopyAndReadColor() {
        manager.copy(UIColor.systemBlue)
        let result = manager.color()
        XCTAssertNotNil(result)
    }

    func testColorIsNilWhenNoneCopied() {
        manager.copy("just text")
        XCTAssertNil(manager.color())
    }

    // MARK: - Inspection

    func testItemCountReflectsSingleCopy() {
        XCTAssertEqual(manager.itemCount, 0)
        manager.copy("one item")
        XCTAssertEqual(manager.itemCount, 1)
    }

    func testClearRemovesAllItems() {
        manager.copy("something")
        XCTAssertTrue(manager.hasStrings)
        manager.clear()
        XCTAssertFalse(manager.hasStrings)
        XCTAssertEqual(manager.itemCount, 0)
    }

    // MARK: - Expiring & Local-Only Options

    func testCopyWithExpirationDoesNotCrashAndIsReadableImmediately() {
        manager.copy("temporary-code", expiresIn: 60)
        XCTAssertEqual(manager.string(), "temporary-code")
    }

    func testCopyWithLocalOnlyDoesNotCrashAndIsReadableImmediately() {
        manager.copy("local-secret", localOnly: true)
        XCTAssertEqual(manager.string(), "local-secret")
    }

    func testCopyWithExpirationAndLocalOnlyCombined() {
        manager.copy(URL(string: "https://secret.example.com")!, expiresIn: 30, localOnly: true)
        XCTAssertEqual(manager.url(), URL(string: "https://secret.example.com"))
    }

    // MARK: - Change Observation

    func testOnChangeFiresWhenPasteboardIsModified() {
        let expectation = expectation(description: "change handler fires")
        manager.onChange {
            expectation.fulfill()
        }
        manager.copy("triggering a change")
        wait(for: [expectation], timeout: 2.0)
    }

    func testRemoveChangeHandlerStopsFutureNotifications() {
        var fireCount = 0
        let token = manager.onChange { fireCount += 1 }
        manager.removeChangeHandler(token)

        let expectation = expectation(description: "grace period elapses")
        manager.copy("should not notify removed handler")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(fireCount, 0)
    }

    func testMultipleChangeHandlersAllFire() {
        let expectationA = expectation(description: "handler A fires")
        let expectationB = expectation(description: "handler B fires")
        manager.onChange { expectationA.fulfill() }
        manager.onChange { expectationB.fulfill() }
        manager.copy("notify everyone")
        wait(for: [expectationA, expectationB], timeout: 2.0)
    }

    // MARK: - Overwrite Semantics

    func testCopyingNewValueOverwritesPrevious() {
        manager.copy("first")
        manager.copy("second")
        XCTAssertEqual(manager.string(), "second")
        XCTAssertEqual(manager.itemCount, 1)
    }
}
