import XCTest
@testable import SwiftUtilsStorage

private actor Recorder {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

private struct BoomError: Error {}

final class MigrationRunnerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MigrationRunnerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRunner(_ policy: MigrationRunner.FreshInstallPolicy = .runAll) -> MigrationRunner {
        MigrationRunner(defaults: defaults, versionKey: "test.version", freshInstallPolicy: policy)
    }

    // MARK: - Ordering

    func testRunsMigrationsInAscendingOrder() async throws {
        let runner = makeRunner()
        let recorder = Recorder()
        try await runner.register(version: 3, name: "three") { await recorder.record("3") }
        try await runner.register(version: 1, name: "one") { await recorder.record("1") }
        try await runner.register(version: 2, name: "two") { await recorder.record("2") }

        let report = try await runner.run()

        let events = await recorder.events
        XCTAssertEqual(events, ["1", "2", "3"])
        XCTAssertEqual(report.applied, ["one", "two", "three"])
        XCTAssertNil(report.startingVersion)
        XCTAssertEqual(report.endingVersion, 3)
        let current = await runner.currentVersion
        XCTAssertEqual(current, 3)
    }

    // MARK: - Idempotence

    func testSecondRunDoesNothing() async throws {
        let runner = makeRunner()
        let recorder = Recorder()
        try await runner.register(version: 1, name: "one") { await recorder.record("1") }

        try await runner.run()
        let report = try await runner.run()

        let events = await recorder.events
        XCTAssertEqual(events, ["1"])
        XCTAssertEqual(report.applied, [])
        XCTAssertEqual(report.startingVersion, 1)
    }

    func testOnlyNewMigrationsRunAfterUpgrade() async throws {
        let recorder = Recorder()
        let first = makeRunner()
        try await first.register(version: 1, name: "one") { await recorder.record("1") }
        try await first.run()

        // Simulate next app version with an additional migration.
        let second = makeRunner()
        try await second.register(version: 1, name: "one") { await recorder.record("1") }
        try await second.register(version: 2, name: "two") { await recorder.record("2") }
        let pending = await second.pendingVersions
        XCTAssertEqual(pending, [2])

        let report = try await second.run()
        let events = await recorder.events
        XCTAssertEqual(events, ["1", "2"])
        XCTAssertEqual(report.applied, ["two"])
    }

    // MARK: - Failure handling

    func testFailureStopsRunAndCommitsEarlierSteps() async throws {
        let runner = makeRunner()
        let recorder = Recorder()
        try await runner.register(version: 1, name: "one") { await recorder.record("1") }
        try await runner.register(version: 2, name: "two") { throw BoomError() }
        try await runner.register(version: 3, name: "three") { await recorder.record("3") }

        do {
            try await runner.run()
            XCTFail("Expected failure")
        } catch MigrationRunner.MigrationError.stepFailed(let version, let name, _) {
            XCTAssertEqual(version, 2)
            XCTAssertEqual(name, "two")
        }

        let events = await recorder.events
        XCTAssertEqual(events, ["1"])
        let current = await runner.currentVersion
        XCTAssertEqual(current, 1)
        let pending = await runner.pendingVersions
        XCTAssertEqual(pending, [2, 3])
    }

    // MARK: - Fresh install policy

    func testSkipAllOnFreshInstallMarksLatestWithoutRunning() async throws {
        let runner = makeRunner(.skipAll)
        let recorder = Recorder()
        try await runner.register(version: 1, name: "one") { await recorder.record("1") }
        try await runner.register(version: 5, name: "five") { await recorder.record("5") }

        let report = try await runner.run()

        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(report.skippedForFreshInstall)
        XCTAssertEqual(report.endingVersion, 5)
        let current = await runner.currentVersion
        XCTAssertEqual(current, 5)
    }

    func testSkipAllStillRunsForExistingInstalls() async throws {
        defaults.set(1, forKey: "test.version")
        let runner = makeRunner(.skipAll)
        let recorder = Recorder()
        try await runner.register(version: 1, name: "one") { await recorder.record("1") }
        try await runner.register(version: 2, name: "two") { await recorder.record("2") }

        let report = try await runner.run()

        let events = await recorder.events
        XCTAssertEqual(events, ["2"])
        XCTAssertFalse(report.skippedForFreshInstall)
    }

    // MARK: - Registration validation

    func testDuplicateVersionThrows() async throws {
        let runner = makeRunner()
        try await runner.register(version: 1, name: "one") {}
        do {
            try await runner.register(version: 1, name: "again") {}
            XCTFail("Expected duplicate error")
        } catch {
            XCTAssertEqual(error as? MigrationRunner.MigrationError, .duplicateVersion(1))
        }
    }

    func testNonPositiveVersionThrows() async {
        let runner = makeRunner()
        do {
            try await runner.register(version: 0, name: "zero") {}
            XCTFail("Expected invalid version error")
        } catch {
            XCTAssertEqual(error as? MigrationRunner.MigrationError, .invalidVersion(0))
        }
    }

    // MARK: - Reset

    func testResetMakesAllMigrationsPendingAgain() async throws {
        let runner = makeRunner()
        try await runner.register(version: 1, name: "one") {}
        try await runner.register(version: 2, name: "two") {}
        try await runner.run()

        await runner.reset()

        let current = await runner.currentVersion
        let pending = await runner.pendingVersions
        XCTAssertNil(current)
        XCTAssertEqual(pending, [1, 2])
    }
}
