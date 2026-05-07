//
//  Logger.swift
//  SwiftUtils
//
//  A lightweight, structured logging utility for iOS applications.
//  Supports log levels, subsystem/category tagging, and pluggable destinations.
//
//  Targets iOS 15+ / Swift 5.9+
//

import Foundation
import os.log

// MARK: - Log Level

/// Severity levels for log messages, ordered from most to least verbose.
public enum LogLevel: Int, Comparable, Sendable, CustomStringConvertible {
    case verbose = 0
    case debug   = 1
    case info    = 2
    case warning = 3
    case error   = 4
    case fatal   = 5

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARNING"
        case .error:   return "ERROR"
        case .fatal:   return "FATAL"
        }
    }

    /// Emoji prefix for console readability.
    public var icon: String {
        switch self {
        case .verbose: return "💬"
        case .debug:   return "🔍"
        case .info:    return "ℹ️"
        case .warning: return "⚠️"
        case .error:   return "❌"
        case .fatal:   return "🔥"
        }
    }
}

// MARK: - Log Destination Protocol

/// A destination that receives formatted log entries.
/// Conform to this protocol to build custom destinations (file, remote, analytics, etc.).
public protocol LogDestination: Sendable {
    /// Called for each log entry that passes the logger's level filter.
    func write(_ entry: LogEntry)
}

// MARK: - Log Entry

/// An immutable snapshot of a single log event.
public struct LogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let category: String?
    public let file: String
    public let function: String
    public let line: UInt

    /// A pre-formatted string suitable for display.
    public var formatted: String {
        let ts = Self.formatter.string(from: timestamp)
        let cat = category.map { "[\($0)] " } ?? ""
        let location = "\(shortFile):\(line)"
        return "\(ts) \(level.icon) \(level) \(cat)\(message) (\(location))"
    }

    private var shortFile: String {
        (file as NSString).lastPathComponent
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Console Destination

/// Writes log entries to the Xcode console / stdout using `os.Logger` when available,
/// falling back to `print` for unit-test visibility.
public final class ConsoleDestination: LogDestination, @unchecked Sendable {
    private let subsystem: String
    private let osLog: os.Logger

    /// - Parameters:
    ///   - subsystem: The subsystem string for `os.Logger` (typically your bundle identifier).
    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.swiftutils") {
        self.subsystem = subsystem
        self.osLog = os.Logger(subsystem: subsystem, category: "general")
    }

    public func write(_ entry: LogEntry) {
        #if DEBUG
        print(entry.formatted)
        #else
        let categoryLog = os.Logger(subsystem: subsystem, category: entry.category ?? "general")
        switch entry.level {
        case .verbose, .debug:
            categoryLog.debug("\(entry.formatted, privacy: .public)")
        case .info:
            categoryLog.info("\(entry.formatted, privacy: .public)")
        case .warning:
            categoryLog.warning("\(entry.formatted, privacy: .public)")
        case .error:
            categoryLog.error("\(entry.formatted, privacy: .public)")
        case .fatal:
            categoryLog.fault("\(entry.formatted, privacy: .public)")
        }
        #endif
    }
}

// MARK: - Logger

/// A configurable, thread-safe logger with pluggable destinations.
///
/// **Quick start:**
/// ```swift
/// let log = SwiftLogger(minimumLevel: .debug)
/// log.debug("User tapped login")
/// log.error("Network request failed", category: "API")
/// ```
///
/// **Custom destinations:**
/// ```swift
/// struct FileDestination: LogDestination { ... }
/// let log = SwiftLogger(minimumLevel: .info, destinations: [ConsoleDestination(), FileDestination()])
/// ```
public final class SwiftLogger: @unchecked Sendable {

    // MARK: - Properties

    /// Messages below this level are discarded.
    public var minimumLevel: LogLevel {
        get { lock.withLock { _minimumLevel } }
        set { lock.withLock { _minimumLevel = newValue } }
    }

    private var _minimumLevel: LogLevel
    private let destinations: [LogDestination]
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a new logger.
    /// - Parameters:
    ///   - minimumLevel: The minimum severity to log. Defaults to `.debug`.
    ///   - destinations: Where log entries are sent. Defaults to a `ConsoleDestination`.
    public init(
        minimumLevel: LogLevel = .debug,
        destinations: [LogDestination] = [ConsoleDestination()]
    ) {
        self._minimumLevel = minimumLevel
        self.destinations = destinations
    }

    // MARK: - Convenience Methods

    /// Log a verbose message.
    public func verbose(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .verbose, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Log a debug message.
    public func debug(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .debug, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Log an informational message.
    public func info(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .info, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Log a warning message.
    public func warning(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .warning, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Log an error message.
    public func error(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .error, message: message(), category: category, file: file, function: function, line: line)
    }

    /// Log a fatal message.
    public func fatal(
        _ message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(level: .fatal, message: message(), category: category, file: file, function: function, line: line)
    }

    // MARK: - Core

    /// The core logging method. Messages below `minimumLevel` are discarded.
    public func log(
        level: LogLevel,
        message: @autoclosure () -> String,
        category: String? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        guard level >= minimumLevel else { return }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message(),
            category: category,
            file: file,
            function: function,
            line: line
        )

        for destination in destinations {
            destination.write(entry)
        }
    }
}

// MARK: - Shared Instance

extension SwiftLogger {
    /// A shared default logger for convenience. Configure at app launch if needed.
    public static let shared = SwiftLogger()
}
