import XCTest
@testable import SwiftUtilsHelpers

private struct Doc: Equatable { var text = "" }

/// Not Equatable, to exercise the unconstrained initializer.
private struct Canvas { var strokes: [Int] = [] }

final class UndoHistoryTests: XCTestCase {

    private final class Clock {
        var time = Date(timeIntervalSince1970: 0)
        func advance(_ seconds: TimeInterval) { time += seconds }
    }

    func testInitialState() {
        let history = UndoHistory(Doc())
        XCTAssertEqual(history.current, Doc())
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertFalse(history.hasUnsavedChanges)
    }

    func testRecordUndoRedo() {
        let history = UndoHistory(0)
        history.record(1, actionName: "One")
        history.record(2, actionName: "Two")
        XCTAssertEqual(history.undoActionName, "Two")
        XCTAssertEqual(history.undo(), 1)
        XCTAssertEqual(history.redoActionName, "Two")
        XCTAssertEqual(history.undo(), 0)
        XCTAssertNil(history.undo())
        XCTAssertEqual(history.redo(), 1)
        XCTAssertEqual(history.redo(), 2)
        XCTAssertNil(history.redo())
        XCTAssertEqual(history.current, 2)
    }

    func testRecordClearsRedoStack() {
        let history = UndoHistory(0)
        history.record(1)
        history.undo()
        XCTAssertTrue(history.canRedo)
        history.record(5)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undo(), 0)
    }

    func testUpdateMutatesCopy() {
        let history = UndoHistory(Doc())
        history.update(actionName: "Type") { $0.text = "Hello" }
        XCTAssertEqual(history.current.text, "Hello")
        history.undo()
        XCTAssertEqual(history.current.text, "")
    }

    func testEquatableValuesSkipDuplicates() {
        let history = UndoHistory(Doc(text: "a"))
        history.record(Doc(text: "a"))
        XCTAssertFalse(history.canUndo)
    }

    func testNonEquatableValuesAlwaysRecord() {
        let history = UndoHistory(Canvas())
        history.record(Canvas())
        history.update { $0.strokes.append(1) }
        XCTAssertEqual(history.undoCount, 2)
        XCTAssertEqual(history.current.strokes, [1])
    }

    func testCoalescingWithinWindow() {
        let clock = Clock()
        let history = UndoHistory("", now: { clock.time })
        history.record("H", coalescingKey: "typing")
        clock.advance(0.5)
        history.record("Hi", coalescingKey: "typing")
        clock.advance(0.5)
        history.record("Hi!", coalescingKey: "typing")
        XCTAssertEqual(history.undoCount, 1)
        XCTAssertEqual(history.undo(), "")
    }

    func testCoalescingBreaksAfterWindowOrKeyChange() {
        let clock = Clock()
        let history = UndoHistory("", now: { clock.time })
        history.record("a", coalescingKey: "typing")
        clock.advance(2)
        history.record("ab", coalescingKey: "typing")
        history.record("AB", coalescingKey: "case")
        history.record("ABC")
        history.record("ABCD")
        XCTAssertEqual(history.undoCount, 5)
    }

    func testLimitDropsOldestSteps() {
        let history = UndoHistory(0, limit: 3)
        (1...5).forEach { history.record($0) }
        XCTAssertEqual(history.undoCount, 3)
        history.undo(); history.undo(); history.undo()
        XCTAssertEqual(history.current, 2)
        XCTAssertFalse(history.canUndo)
    }

    func testSavedStateTracking() {
        let history = UndoHistory(0)
        history.record(1)
        XCTAssertTrue(history.hasUnsavedChanges)
        history.markSaved()
        XCTAssertFalse(history.hasUnsavedChanges)
        history.record(2)
        XCTAssertTrue(history.hasUnsavedChanges)
        history.undo()
        XCTAssertFalse(history.hasUnsavedChanges, "Undoing back to the saved value is clean")
        history.undo()
        XCTAssertTrue(history.hasUnsavedChanges)
        history.redo()
        XCTAssertFalse(history.hasUnsavedChanges)
    }

    func testClearKeepsCurrentValue() {
        let history = UndoHistory(0)
        history.record(1); history.record(2); history.undo()
        history.clear()
        XCTAssertEqual(history.current, 1)
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testOnChangeFiresForEveryChange() {
        let history = UndoHistory(0)
        var seen: [Int] = []
        history.onChange { seen.append($0) }
        history.record(1)
        history.record(1) // duplicate, ignored
        history.undo()
        history.redo()
        history.undo(); history.undo() // second undo is a no-op
        XCTAssertEqual(seen, [1, 0, 1, 0])
    }

    func testConcurrentRecordsAreSafe() {
        let history = UndoHistory(0, limit: 10_000)
        DispatchQueue.concurrentPerform(iterations: 500) { i in
            history.record(i + 1)
        }
        XCTAssertEqual(history.undoCount, 500)
    }
}
