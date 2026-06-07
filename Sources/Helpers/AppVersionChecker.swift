import Foundation

// MARK: - Version

/// A comparable semantic version (major.minor.patch).
public struct Version: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Creates a `Version` from a dot-separated string such as `"2.1.3"`.
    /// Returns `nil` if the string cannot be parsed.
    public init?(_ string: String) {
        let parts = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) }
        guard parts.count >= 1,
              let major = parts[0] else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? (parts[1] ?? 0) : 0
        self.patch = parts.count > 2 ? (parts[2] ?? 0) : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - VersionCheckResult

/// The outcome of comparing the installed app version with the App Store version.
public enum VersionCheckResult: Equatable {
    /// The installed version matches the latest App Store release.
    case upToDate
    /// A newer version is available. Associates the `Version` available on the store.
    case updateAvailable(latestVersion: Version)
    /// The installed version is newer than the store (e.g. TestFlight / dev build).
    case aheadOfStore
}

// MARK: - AppVersionCheckerError

/// Errors thrown by `AppVersionChecker`.
public enum AppVersionCheckerError: Error, LocalizedError {
    case bundleIdentifierMissing
    case invalidResponse
    case appNotFoundOnAppStore

    public var errorDescription: String? {
        switch self {
        case .bundleIdentifierMissing:  return "No bundle identifier found in the app bundle."
        case .invalidResponse:          return "The App Store returned an unexpected response."
        case .appNotFoundOnAppStore:    return "The app was not found on the App Store."
        }
    }
}

// MARK: - AppVersionChecker

/// Fetches the latest App Store version for the running app and compares it with
/// the installed version. Uses the iTunes Lookup API — no third-party dependencies.
///
/// ```swift
/// let result = try await AppVersionChecker.shared.check()
/// if case .updateAvailable(let latest) = result {
///     print("Update to \(latest) is available")
/// }
/// ```
public final class AppVersionChecker {

    // MARK: Public

    /// Shared singleton — suitable for most apps.
    public static let shared = AppVersionChecker()

    /// The installed app version read from `CFBundleShortVersionString`.
    public var installedVersion: Version? {
        guard let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return Version(raw)
    }

    // MARK: Init

    /// Creates an independent checker. Useful for testing with a custom `URLSession`.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Check

    /// Fetches the current App Store version and returns a `VersionCheckResult`.
    ///
    /// - Parameter countryCode: Two-letter ISO country code for the App Store lookup.
    ///   Defaults to `"us"`.
    /// - Returns: A `VersionCheckResult` describing whether an update is available.
    /// - Throws: `AppVersionCheckerError` or a networking error.
    @discardableResult
    public func check(countryCode: String = "us") async throws -> VersionCheckResult {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw AppVersionCheckerError.bundleIdentifierMissing
        }

        let storeVersion = try await fetchStoreVersion(bundleId: bundleId, countryCode: countryCode)

        guard let installed = installedVersion else {
            return .updateAvailable(latestVersion: storeVersion)
        }

        if installed < storeVersion  { return .updateAvailable(latestVersion: storeVersion) }
        if installed > storeVersion  { return .aheadOfStore }
        return .upToDate
    }

    /// Fetches only the latest version string from the App Store without comparing.
    ///
    /// - Parameter countryCode: Two-letter ISO country code. Defaults to `"us"`.
    /// - Returns: The latest `Version` listed on the App Store.
    public func latestStoreVersion(countryCode: String = "us") async throws -> Version {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw AppVersionCheckerError.bundleIdentifierMissing
        }
        return try await fetchStoreVersion(bundleId: bundleId, countryCode: countryCode)
    }

    // MARK: - Private

    private let session: URLSession

    private func fetchStoreVersion(bundleId: String, countryCode: String) async throws -> Version {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country",  value: countryCode),
        ]

        let (data, _) = try await session.data(from: components.url!)

        struct LookupResponse: Decodable {
            let resultCount: Int
            let results: [AppResult]
            struct AppResult: Decodable {
                let version: String
            }
        }

        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard response.resultCount > 0, let versionString = response.results.first?.version else {
            throw AppVersionCheckerError.appNotFoundOnAppStore
        }
        guard let version = Version(versionString) else {
            throw AppVersionCheckerError.invalidResponse
        }
        return version
    }
}
