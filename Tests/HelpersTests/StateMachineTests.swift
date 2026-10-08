import XCTest
@testable import SwiftUtilsHelpers

private enum Player: Hashable { case idle, playing, paused, error }
private enum Action: Hashable { case play, pause, stop, fail }

final class StateMachineTests: XCTestCase {

    private typealias Machine = StateMachine<Player, Action>

    private func makeMachine(historyLimit: Int = 50) -> Machine {
        let machine = Machine(initial: .idle, historyLimit: historyLimit)
        machine.addRoute(from: [.idle, .paused], on: .play, to: .playing)
        machine.addRoute(from: .playing, on: .pause, to: .paused)
        machine.addRoute(fromAnyOn: .stop, to: .idle)
        return machine
    }

    func testInitialState() {
        XCTAssertEqual(makeMachine().state, .idle)
    }

    func testValidTransitionsUpdateState() throws {
        let machine = makeMachine()
        XCTAssertEqual(try machine.fire(.play), .playing)
        XCTAssertEqual(try machine.fire(.pause), .paused)
        XCTAssertEqual(try machine.fire(.play), .playing)
        XCTAssertEqual(machine.state, .playing)
    }

    func testInvalidTransitionThrowsNoRoute() {
        let machine = makeMachine()
        XCTAssertThrowsError(try machine.fire(.pause)) { error in
            XCTAssertEqual(error as? Machine.TransitionError, .noRoute(from: .idle, event: .pause))
        }
        XCTAssertEqual(machine.state, .idle)
    }

    func testWildcardRouteAppliesFromAnyState() throws {
        let machine = makeMachine()
        try machine.fire(.play)
        try machine.fire(.stop)
        XCTAssertEqual(machine.state, .idle)
        try machine.fire(.stop)
        XCTAssertEqual(machine.state, .idle)
    }

    func testSpecificRouteTakesPrecedenceOverWildcard() throws {
        let machine = makeMachine()
        machine.addRoute(from: .paused, on: .stop, to: .error)
        try machine.fire(.play)
        try machine.fire(.pause)
        XCTAssertEqual(try machine.fire(.stop), .error)
    }

    func testGuardRejectsTransition() {
        var allowed = false
        let machine = Machine(initial: .idle)
        machine.addRoute(from: .idle, on: .play, to: .playing, guard: { _ in allowed })

        XCTAssertFalse(machine.canFire(.play))
        XCTAssertThrowsError(try machine.fire(.play)) { error in
            XCTAssertEqual(error as? Machine.TransitionError, .guardRejected(from: .idle, event: .play))
        }
        allowed = true
        XCTAssertTrue(machine.canFire(.play))
        XCTAssertTrue(machine.tryFire(.play))
        XCTAssertEqual(machine.state, .playing)
    }

    func testDestinationAndCanFire() {
        let machine = makeMachine()
        XCTAssertEqual(machine.destination(for: .play), .playing)
        XCTAssertNil(machine.destination(for: .pause))
        XCTAssertTrue(machine.canFire(.stop))
    }

    func testTryFireReturnsFalseWithoutChangingState() {
        let machine = makeMachine()
        XCTAssertFalse(machine.tryFire(.pause))
        XCTAssertEqual(machine.state, .idle)
    }

    func testHooksRunInExitEnterTransitionOrder() throws {
        let machine = makeMachine()
        var log: [String] = []
        machine.onExit(.idle) { _ in log.append("exit idle") }
        machine.onEnter(.playing) { _ in log.append("enter playing") }
        machine.onTransition { t in log.append("transition \(t.from)->\(t.to)") }

        try machine.fire(.play)
        XCTAssertEqual(log, ["exit idle", "enter playing", "transition idle->playing"])
    }

    func testHooksNotCalledOnFailedTransition() {
        let machine = makeMachine()
        var called = false
        machine.onTransition { _ in called = true }
        _ = machine.tryFire(.pause)
        XCTAssertFalse(called)
    }

    func testReentrantFireFromEnterHook() throws {
        let machine = makeMachine()
        machine.addRoute(from: .playing, on: .fail, to: .error)
        machine.onEnter(.playing) { _ in _ = machine.tryFire(.fail) }
        try machine.fire(.play)
        XCTAssertEqual(machine.state, .error)
    }

    func testHistoryRecordsAndIsCapped() throws {
        let machine = makeMachine(historyLimit: 2)
        try machine.fire(.play)
        try machine.fire(.pause)
        try machine.fire(.play)
        XCTAssertEqual(machine.history, [
            .init(from: .playing, event: .pause, to: .paused),
            .init(from: .paused, event: .play, to: .playing),
        ])
    }

    func testZeroHistoryLimitDisablesHistory() throws {
        let machine = makeMachine(historyLimit: 0)
        try machine.fire(.play)
        XCTAssertTrue(machine.history.isEmpty)
    }

    func testResetSetsStateAndClearsHistoryWithoutHooks() throws {
        let machine = makeMachine()
        var entered = false
        machine.onEnter(.paused) { _ in entered = true }
        try machine.fire(.play)
        machine.reset(to: .paused)
        XCTAssertEqual(machine.state, .paused)
        XCTAssertTrue(machine.history.isEmpty)
        XCTAssertFalse(entered)
    }

    func testConcurrentFiringIsSafe() {
        let machine = Machine(initial: .idle)
        machine.addRoute(from: .idle, on: .play, to: .playing)
        machine.addRoute(from: .playing, on: .stop, to: .idle)
        DispatchQueue.concurrentPerform(iterations: 1_000) { i in
            _ = machine.tryFire(i.isMultiple(of: 2) ? .play : .stop)
        }
        XCTAssertTrue([.idle, .playing].contains(machine.state))
        XCTAssertLessThanOrEqual(machine.history.count, 50)
    }
}
