import XCTest
@testable import SwiftUtilsHelpers

// MARK: - RunRecord Tests

final class BackgroundTaskManagerRunRecordTests: XCTestCase {

    func testDurationComputesElapsedTime() {
        let started = Date()
        let finished = started.addingTimeInterval(4.5)
        let record = BackgroundTaskManager.RunRecord(
            identifier: "com.app.refresh",
            startedAt: started,
            finishedAt: finished,
            succeeded: true,
            expired: false
        )
        XCTAssertEqual(record.duration, 4.5, accuracy: 0.0001)
    }

    func testRunRecordEquality() {
        let started = Date()
        let finished = started.addingTimeInterval(1)
        let a = BackgroundTaskManager.RunRecord(
            identifier: "id", startedAt: started, finishedAt: finished, succeeded: true, expired: false
        )
        let b = BackgroundTaskManager.RunRecord(
            identifier: "id", startedAt: started, finishedAt: finished, succeeded: true, expired: false
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - Run Log Tests

final class BackgroundTaskManagerRunLogTests: XCTestCase {

    func testRecentRunsStartsEmpty() {
        let manager = BackgroundTaskManager(maxRecords: 5)
        XCTAssertTrue(manager.recentRuns.isEmpty)
    }

    func testLastRunReturnsNilWhenNoHistory() {
        let manager = BackgroundTaskManager(maxRecords: 5)
        XCTAssertNil(manager.lastRun(for: "com.app.refresh"))
    }

    func testRecordInsertsNewestFirst() {
        let manager = BackgroundTaskManager(maxRecords: 5)
        let first = Date()
        let second = first.addingTimeInterval(60)

        manager.record(identifier: "com.app.refresh", startedAt: first, succeeded: true, expired: false)
        manager.record(identifier: "com.app.refresh", startedAt: second, succeeded: false, expired: true)

        let runs = manager.recentRuns
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first?.startedAt, second)
        XCTAssertEqual(runs.first?.succeeded, false)
        XCTAssertEqual(runs.first?.expired, true)
        XCTAssertEqual(runs.last?.startedAt, first)
    }

    func testRecordTrimsToMaxRecords() {
        let manager = BackgroundTaskManager(maxRecords: 3)
        for i in 0..<10 {
            manager.record(
                identifier: "com.app.refresh",
                startedAt: Date().addingTimeInterval(TimeInterval(i)),
                succeeded: true,
                expired: false
            )
        }
        XCTAssertEqual(manager.recentRuns.count, 3)
    }

    func testLastRunFiltersByIdentifier() {
        let manager = BackgroundTaskManager(maxRecords: 10)
        manager.record(identifier: "com.app.refresh", startedAt: Date(), succeeded: true, expired: false)
        manager.record(identifier: "com.app.sync", startedAt: Date(), succeeded: false, expired: false)
        manager.record(identifier: "com.app.refresh", startedAt: Date(), succeeded: false, expired: true)

        let lastRefresh = manager.lastRun(for: "com.app.refresh")
        XCTAssertEqual(lastRefresh?.identifier, "com.app.refresh")
        XCTAssertEqual(lastRefresh?.expired, true)

        let lastSync = manager.lastRun(for: "com.app.sync")
        XCTAssertEqual(lastSync?.succeeded, false)

        XCTAssertNil(manager.lastRun(for: "com.app.unknown"))
    }

    func testIndependentInstancesDoNotShareState() {
        let a = BackgroundTaskManager(maxRecords: 5)
        let b = BackgroundTaskManager(maxRecords: 5)

        a.record(identifier: "com.app.refresh", startedAt: Date(), succeeded: true, expired: false)

        XCTAssertEqual(a.recentRuns.count, 1)
        XCTAssertTrue(b.recentRuns.isEmpty)
    }
}

// MARK: - SchedulingError Tests

final class BackgroundTaskManagerSchedulingErrorTests: XCTestCase {

    func testBackgroundTasksUnavailableDescription() {
        let error = BackgroundTaskManager.SchedulingError.backgroundTasksUnavailable
        XCTAssertEqual(error.errorDescription, "BackgroundTasks framework is unavailable on this platform.")
    }

    func testUnderlyingErrorDescriptionWrapsMessage() {
        struct DummyError: LocalizedError {
            var errorDescription: String? { "disk full" }
        }
        let error = BackgroundTaskManager.SchedulingError.underlying(DummyError())
        XCTAssertEqual(error.errorDescription, "Failed to submit background task request: disk full")
    }
}
