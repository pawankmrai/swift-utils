import Foundation

// MARK: - LaunchFlag

/// A boolean command-line flag such as `-uiTesting` or a truthy environment variable.
public struct LaunchFlag: Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String

    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }

    public var description: String { name }
}

extension LaunchFlag {
    /// Marks the process as running under UI Testing.
    public static let uiTesting: LaunchFlag = "UI_TESTING"
    /// Requests that persisted app state (Keychain, UserDefaults, files) be wiped at launch.
    public static let resetState: LaunchFlag = "RESET_STATE"
    /// Skips onboarding / first-run flows.
    public static let skipOnboarding: LaunchFlag = "SKIP_ONBOARDING"
    /// Disables UIView/Core Animation animations for deterministic UI test timing.
    public static let disableAnimations: LaunchFlag = "DISABLE_ANIMATIONS"
    /// Routes networking through stubbed/mock responses instead of live servers.
    public static let mockNetwork: LaunchFlag = "MOCK_NETWORK"
}

// MARK: - LaunchOption

/// A key for a `-key value` launch argument or `key=value` environment variable.
public struct LaunchOption: Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String

    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }

    public var description: String { name }
}

extension LaunchOption {
    /// Overrides the app's active locale identifier, e.g. `"fr_FR"`.
    public static let locale: LaunchOption = "LAUNCH_LOCALE"
    /// An ISO 8601 timestamp the app should treat as "now", for deterministic date-based tests.
    public static let mockDate: LaunchOption = "MOCK_DATE"
    /// The name of a bundled JSON fixture used to seed local data at launch.
    public static let seedFile: LaunchOption = "SEED_FILE"
}

// MARK: - LaunchArguments

/// Type-safe access to `ProcessInfo` launch arguments and environment variables.
///
/// Apps commonly need to alter their behavior when launched from UI tests or QA
/// builds — skipping onboarding, disabling animations, seeding fixture data, or
/// mocking the current date. `LaunchArguments` gives that configuration a single,
/// typed entry point instead of scattering raw `ProcessInfo` string checks
/// throughout the codebase.
///
/// Two argument shapes are recognized:
/// - Bare flags: `-uiTesting`
/// - Key/value pairs: `-mockDate 2024-01-01T00:00:00Z`
///
/// Environment variables (`launchEnvironment` on `XCUIApplication`) are also read,
/// and are used as a fallback when the matching argument isn't present.
///
/// ```swift
/// if LaunchArguments.current.contains(.uiTesting) {
///     UIView.setAnimationsEnabled(false)
/// }
/// ```
public struct LaunchArguments {

    /// Parses `ProcessInfo.processInfo` at access time. Safe to call repeatedly;
    /// process arguments/environment don't change during a run.
    public static var current: LaunchArguments {
        LaunchArguments(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// The raw process arguments, equivalent to `ProcessInfo.processInfo.arguments`.
    public let arguments: [String]
    /// The raw process environment variables.
    public let environment: [String: String]

    private let optionValues: [String: String]

    /// Creates a parser over explicit arguments/environment. Primarily useful for
    /// unit testing app logic that depends on `LaunchArguments` without spawning a process.
    public init(arguments: [String], environment: [String: String] = [:]) {
        self.arguments = arguments
        self.environment = environment
        self.optionValues = Self.parseOptions(from: arguments)
    }

    private static func parseOptions(from arguments: [String]) -> [String: String] {
        var parsed: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token.hasPrefix("-") {
                let next = index + 1 < arguments.count ? arguments[index + 1] : nil
                if let next, !next.hasPrefix("-") {
                    parsed[strip(token)] = next
                    index += 2
                    continue
                }
            }
            index += 1
        }
        return parsed
    }

    private static func strip(_ token: String) -> String {
        var name = token
        while name.hasPrefix("-") { name.removeFirst() }
        return name
    }

    // MARK: Flags

    /// Returns `true` if `flag` is present as a bare argument (`-flagName`) or as a
    /// truthy environment variable (`"1"`, `"true"`, or `"yes"`, case-insensitive).
    public func contains(_ flag: LaunchFlag) -> Bool {
        if arguments.contains(where: { Self.strip($0) == flag.name }) {
            return true
        }
        if let raw = environment[flag.name] {
            return ["1", "true", "yes"].contains(raw.lowercased())
        }
        return false
    }

    // MARK: Options

    /// Returns the raw string value for `option`, preferring a `-key value` argument
    /// pair and falling back to the environment.
    public func value(for option: LaunchOption) -> String? {
        optionValues[option.name] ?? environment[option.name]
    }

    /// Returns the value for `option` converted to `T` via `LosslessStringConvertible`
    /// (e.g. `Int`, `Double`, `Bool`). Returns `nil` if the value is missing or malformed.
    public func typedValue<T: LosslessStringConvertible>(for option: LaunchOption, as type: T.Type = T.self) -> T? {
        value(for: option).flatMap(T.init)
    }

    /// Decodes the value for `option` as a JSON string into `T`. Useful for seeding
    /// structured fixture data, e.g. `-SEED_FILE '{"userCount":3,"isPro":true}'`.
    public func decode<T: Decodable>(
        _ type: T.Type,
        for option: LaunchOption,
        decoder: JSONDecoder = JSONDecoder()
    ) -> T? {
        guard let raw = value(for: option), let data = raw.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// `true` when the process was launched by XCTest — either because `.uiTesting`
    /// was explicitly set, or because Xcode's `XCTestConfigurationFilePath` environment
    /// variable is present (set automatically for any XCTest run, including unit tests).
    public var isRunningUITests: Bool {
        contains(.uiTesting) || environment["XCTestConfigurationFilePath"] != nil
    }
}

// MARK: - LaunchArgumentsBuilder

/// Builds matching `launchArguments` / `launchEnvironment` values from the test target,
/// mirroring the flags and options read by `LaunchArguments` in the app target.
///
/// ```swift
/// let app = XCUIApplication()
/// let config = LaunchArgumentsBuilder()
///     .flag(.uiTesting)
///     .flag(.skipOnboarding)
///     .option(.mockDate, "2024-01-01T00:00:00Z")
/// app.launchArguments = config.launchArguments
/// app.launchEnvironment = config.launchEnvironment
/// app.launch()
/// ```
public final class LaunchArgumentsBuilder {
    private var arguments: [String] = []
    private var environmentValues: [String: String] = [:]

    public init() {}

    /// Adds a bare `-flagName` argument.
    @discardableResult
    public func flag(_ flag: LaunchFlag) -> Self {
        arguments.append("-\(flag.name)")
        return self
    }

    /// Adds a `-key value` argument pair.
    @discardableResult
    public func option(_ option: LaunchOption, _ value: String) -> Self {
        arguments.append("-\(option.name)")
        arguments.append(value)
        return self
    }

    /// Sets `value` in the assembled environment under `key.name`, for consumers that
    /// prefer reading configuration from `launchEnvironment` instead of arguments.
    @discardableResult
    public func environment(_ key: LaunchOption, _ value: String) -> Self {
        environmentValues[key.name] = value
        return self
    }

    /// The assembled argument list, suitable for `XCUIApplication.launchArguments`.
    public var launchArguments: [String] { arguments }

    /// The assembled environment dictionary, suitable for `XCUIApplication.launchEnvironment`.
    public var launchEnvironment: [String: String] { environmentValues }
}
