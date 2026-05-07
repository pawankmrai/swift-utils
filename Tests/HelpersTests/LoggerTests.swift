//
//  LoggerTests.swift
//  SwiftUtils
//

import XCTest
@testable import SwiftUtilsHelpers

// MARK: - Spy Destination

/// Captures log entries for assertion in tests.
final class SpyDestination: LogDestination, @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [LogEntry] = []

    var entries: [LogEntry] {
        lock.withLock { _entries }
    }

    var lastEntry: LogEntry? {
        entries.last
    }

    func write(_ entry: LogEntry) {
        lock.withLock { _entries.append(entry) }
    }

    func reset() {
        lock.withLock { _entries.removeAll() }
    }
}

// MARK: - LogLevel Tests

final class LogLevelTests: XCTestCase {

    func testLevelOrdering() {
        XCTAssertTrue(LogLevel.verbose < LogLevel.debug)
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.fatal)
    }

    func testLevelDescriptions() {
        XCTAssertEqual(LogLevel.verbose.description, "VERBOSE")
        XCTAssertEqual(LogLevel.debug.description, "DEBUG")
        XCTAssertEqual(LogLevel.info.description, "INFO")
        XCTAssertEqual(LogLevel.warning.description, "WARNING")
        XCTAssertEqual(LogLevel.error.description, "ERROR")
        XCTAssertEqual(LogLevel.fatal.description, "FATAL")
    }

    func testLevelIcons() {
        XCTAssertFalse(LogLevel.verbose.icon.isEmpty)
        XCTAssertFalse(LogLevel.error.icon.isEmpty)
    }
}

// MARK: - SwiftLogger Tests

final class SwiftLoggerTests: XCTestCase {

    private var spy: SpyDestination!
    private var logger: SwiftLogger!

    override func setUp() {
        super.setUp()
        spy = SpyDestination()
        logger = SwiftLogger(minimumLevel: .debug, destinations: [spy])
    }

    func testLogsAtOrAboveMinimumLevel() {
        logger.debug("d")
        logger.info("i")
        logger.warning("w")
        logger.error("e")
        logger.fatal("f")

        XCTAssertEqual(spy.entries.count, 5)
    }

    func testFiltersBelowMinimumLevel() {
        logger.minimumLevel = .warning

        logger.verbose("v")
        logger.debug("d")
        logger.info("i")
        logger.warning("w")
        logger.error("e")

        XCTAssertEqual(spy.entries.count, 2)
        XCTAssertEqual(spy.entries[0].level, .warning)
        XCTAssertEqual(spy.entries[1].level, .error)
    }

    func testVerboseFilteredByDefault() {
        logger.verbose("should be filtered")
        XCTAssertTrue(spy.entries.isEmpty)
    }

    func testMessageContent() {
        logger.info("Hello, world!")
        XCTAssertEqual(spy.lastEntry?.message, "Hello, world!")
        XCTAssertEqual(spy.lastEntry?.level, .info)
    }

    func testCategoryIsRecorded() {
        logger.error("fail", category: "Network")
        XCTAssertEqual(spy.lastEntry?.category, "Network")
    }

    func testCategoryIsNilByDefault() {
        logger.info("no category")
        XCTAssertNil(spy.lastEntry?.category)
    }

    func testEntryFormattedContainsLevel() {
        logger.warning("careful")
        let formatted = spy.lastEntry!.formatted
        XCTAssertTrue(formatted.contains("WARNING"))
    }

    func testEntryFormattedContainsCategory() {
        logger.info("tagged", category: "Auth")
        let formatted = spy.lastEntry!.formatted
        XCTAssertTrue(formatted.contains("[Auth]"))
    }

    func testEntryFormattedContainsFilename() {
        logger.debug("file check")
        let formatted = spy.lastEntry!.formatted
        XCTAssertTrue(formatted.contains("LoggerTests.swift"))
    }

    func testMinimumLevelCanBeChanged() {
        logger.minimumLevel = .fatal
        logger.error("should not appear")
        XCTAssertTrue(spy.entries.isEmpty)

        logger.fatal("should appear")
        XCTAssertEqual(spy.entries.count, 1)
    }

    func testMultipleDestinations() {
        let spy2 = SpyDestination()
        let multiLogger = SwiftLogger(minimumLevel: .debug, destinations: [spy, spy2])
        multiLogger.info("broadcast")

        XCTAssertEqual(spy.entries.count, 1)
        XCTAssertEqual(spy2.entries.count, 1)
    }

    func testAutoClosureDoesNotEvaluateWhenFiltered() {
        var evaluated = false
        logger.minimumLevel = .error

        logger.debug({
            evaluated = true
            return "expensive computation"
        }())

        XCTAssertFalse(evaluated)
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(SwiftLogger.shared)
    }
}
