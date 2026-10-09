import Foundation

/// A thread-safe, snapshot-based undo/redo history for any value type, with
/// named actions, time-window coalescing, a bounded depth, and saved-state
/// ("dirty") tracking.
///
/// Unlike `UndoManager`, which needs an inverse closure for every change,
/// `UndoHistory` simply records successive values of your model. It works
/// naturally with value types (structs, arrays, enums) and SwiftUI state.
///
/// ```swift
/// let history = UndoHistory(Document(text: ""))
/// history.update(actionName: "Typing", coalescingKey: "typing") { $0.text += "Hi" }
/// history.undo()          // back to ""
/// history.redo()          // "Hi" again
/// history.hasUnsavedChanges // true until markSaved()
/// ```
public final class UndoHistory<Value>: @unchecked Sendable {

    /// A recorded snapshot with the name of the action that replaced it.
    private struct Entry {
        var value: Value
        var id: UInt64
        var actionName: String?
        var coalescingKey: String?
        var timestamp: Date
    }

    private let lock = NSLock()
    private let isEqual: ((Value, Value) -> Bool)?
    private let now: () -> Date
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private var _current: Value
    private var currentID: UInt64 = 0
    private var nextID: UInt64 = 1
    private var savedID: UInt64? = 0
    private var changeHandler: ((Value) -> Void)?

    /// Maximum number of undo steps retained. Oldest steps are discarded first.
    public let limit: Int

    /// Creates a history starting at `initial`.
    /// - Parameters:
    ///   - initial: The starting value (treated as the saved state).
    ///   - limit: Maximum undo depth. Defaults to 100.
    ///   - isEqual: Optional equality check; recording an equal value is a no-op.
    ///   - now: Clock used for coalescing. Injectable for tests.
    public init(_ initial: Value, limit: Int = 100,
                isEqual: ((Value, Value) -> Bool)? = nil,
                now: @escaping () -> Date = Date.init) {
        self._current = initial
        self.limit = max(1, limit)
        self.isEqual = isEqual
        self.now = now
    }

    // MARK: - State

    /// The current value.
    public var current: Value { withLock { _current } }
    /// Whether there is a step to undo.
    public var canUndo: Bool { withLock { !undoStack.isEmpty } }
    /// Whether there is a step to redo.
    public var canRedo: Bool { withLock { !redoStack.isEmpty } }
    /// Number of available undo steps.
    public var undoCount: Int { withLock { undoStack.count } }
    /// Number of available redo steps.
    public var redoCount: Int { withLock { redoStack.count } }
    /// Name of the action `undo()` would revert, e.g. for an "Undo Typing" menu title.
    public var undoActionName: String? { withLock { undoStack.last?.actionName } }
    /// Name of the action `redo()` would re-apply.
    public var redoActionName: String? { withLock { redoStack.last?.actionName } }
    /// `true` when the current value differs from the last value passed to ``markSaved()``.
    public var hasUnsavedChanges: Bool { withLock { savedID != currentID } }

    // MARK: - Recording

    /// Records `newValue` as the current value, making the previous value undoable.
    ///
    /// Consecutive records sharing a non-nil `coalescingKey` within
    /// `coalescingWindow` seconds merge into one undo step (e.g. keystrokes).
    /// Any record clears the redo stack.
    public func record(_ newValue: Value, actionName: String? = nil,
                       coalescingKey: String? = nil, coalescingWindow: TimeInterval = 1.0) {
        let value: Value? = withLock {
            if let isEqual, isEqual(_current, newValue) { return nil }
            let time = now()
            if let key = coalescingKey, redoStack.isEmpty, var last = undoStack.last,
               last.coalescingKey == key, time.timeIntervalSince(last.timestamp) <= coalescingWindow {
                last.timestamp = time
                undoStack[undoStack.count - 1] = last
            } else {
                undoStack.append(Entry(value: _current, id: currentID, actionName: actionName,
                                       coalescingKey: coalescingKey, timestamp: time))
                if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
            }
            redoStack.removeAll()
            _current = newValue
            currentID = nextID
            nextID += 1
            return newValue
        }
        if let value { changeHandler?(value) }
    }

    /// Mutates a copy of the current value in place and records the result.
    public func update(actionName: String? = nil, coalescingKey: String? = nil,
                       coalescingWindow: TimeInterval = 1.0, _ mutate: (inout Value) -> Void) {
        var copy = current
        mutate(&copy)
        record(copy, actionName: actionName, coalescingKey: coalescingKey, coalescingWindow: coalescingWindow)
    }

    // MARK: - Undo / Redo

    /// Reverts the most recent step. Returns the restored value, or `nil` if nothing to undo.
    @discardableResult
    public func undo() -> Value? {
        let value: Value? = withLock {
            guard let entry = undoStack.popLast() else { return nil }
            redoStack.append(Entry(value: _current, id: currentID, actionName: entry.actionName,
                                   coalescingKey: nil, timestamp: entry.timestamp))
            _current = entry.value
            currentID = entry.id
            return entry.value
        }
        if let value { changeHandler?(value) }
        return value
    }

    /// Re-applies the most recently undone step. Returns the value, or `nil` if nothing to redo.
    @discardableResult
    public func redo() -> Value? {
        let value: Value? = withLock {
            guard let entry = redoStack.popLast() else { return nil }
            undoStack.append(Entry(value: _current, id: currentID, actionName: entry.actionName,
                                   coalescingKey: nil, timestamp: now()))
            _current = entry.value
            currentID = entry.id
            return entry.value
        }
        if let value { changeHandler?(value) }
        return value
    }

    // MARK: - Housekeeping

    /// Marks the current value as saved; ``hasUnsavedChanges`` becomes `false`.
    public func markSaved() { withLock { savedID = currentID } }

    /// Discards all undo/redo steps while keeping the current value.
    public func clear() { withLock { undoStack.removeAll(); redoStack.removeAll() } }

    /// Registers a handler called (outside the lock) whenever `current` changes.
    public func onChange(_ handler: @escaping (Value) -> Void) { withLock { changeHandler = handler } }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

public extension UndoHistory where Value: Equatable {
    /// Creates a history that ignores records equal to the current value.
    convenience init(_ initial: Value, limit: Int = 100, now: @escaping () -> Date = Date.init) {
        self.init(initial, limit: limit, isEqual: ==, now: now)
    }
}
