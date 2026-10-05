import Foundation

/// Runs versioned, one-time data migrations exactly once per install —
/// the app-level equivalent of database schema migrations.
///
/// Every app eventually needs "run this once after upgrading" logic: rename a
/// `UserDefaults` key, move files out of `Caches`, re-encode a stored model,
/// purge a legacy Keychain item. Ad-hoc `if !defaults.bool(forKey: "didX")`
/// flags pile up fast. `MigrationRunner` replaces them with an ordered list of
/// numbered steps and a single persisted schema version.
///
/// - Migrations run in ascending `version` order.
/// - Only migrations newer than the persisted version run.
/// - The version is persisted **after each successful step**, so if step 3
///   throws, steps 1–2 are not re-run next launch and step 3 is retried.
/// - On a fresh install you can skip everything (there is no legacy data to
///   migrate) via ``FreshInstallPolicy/skipAll``.
///
/// ## Quick start
/// ```swift
/// let runner = MigrationRunner()
/// await runner.register(version: 1, name: "Rename theme key") {
///     let d = UserDefaults.standard
///     d.set(d.string(forKey: "theme"), forKey: "appearance.theme")
///     d.removeObject(forKey: "theme")
/// }
/// let report = try await runner.run()
/// ```
public actor MigrationRunner {

    /// A single numbered migration step.
    public struct Migration: Sendable {
        /// Strictly increasing, unique version number.
        public let version: Int
        /// Human-readable name used in reports and logs.
        public let name: String
        /// The work to perform. Should be idempotent where practical.
        public let work: @Sendable () async throws -> Void
    }

    /// What to do when no schema version has ever been persisted.
    public enum FreshInstallPolicy: Sendable {
        /// Run every registered migration (treat as upgrading from version 0).
        case runAll
        /// Mark the latest version as applied without running anything.
        case skipAll
    }

    /// Errors thrown by ``MigrationRunner``.
    public enum MigrationError: Error, Equatable {
        /// Two migrations were registered with the same version number.
        case duplicateVersion(Int)
        /// Versions must be positive.
        case invalidVersion(Int)
        /// A migration step threw; earlier steps were committed.
        case stepFailed(version: Int, name: String, underlying: String)
    }

    /// Summary of a ``run()`` invocation.
    public struct Report: Sendable, Equatable {
        /// Persisted version before the run (`nil` for a fresh install).
        public let startingVersion: Int?
        /// Persisted version after the run.
        public let endingVersion: Int
        /// Names of the migrations that actually executed, in order.
        public let applied: [String]
        /// `true` when the fresh-install policy skipped all steps.
        public let skippedForFreshInstall: Bool
    }

    private let defaults: UserDefaults
    private let versionKey: String
    private let freshInstallPolicy: FreshInstallPolicy
    private var migrations: [Int: Migration] = [:]

    /// Creates a runner.
    /// - Parameters:
    ///   - defaults: Where the applied schema version is stored.
    ///   - versionKey: The `UserDefaults` key holding the schema version.
    ///   - freshInstallPolicy: Behavior when no version has been persisted yet.
    public init(
        defaults: UserDefaults = .standard,
        versionKey: String = "swiftutils.migrations.version",
        freshInstallPolicy: FreshInstallPolicy = .runAll
    ) {
        self.defaults = defaults
        self.versionKey = versionKey
        self.freshInstallPolicy = freshInstallPolicy
    }

    /// The last successfully applied migration version, or `nil` if none.
    public var currentVersion: Int? {
        defaults.object(forKey: versionKey) as? Int
    }

    /// The highest registered version (0 if nothing is registered).
    public var latestVersion: Int { migrations.keys.max() ?? 0 }

    /// Versions registered but not yet applied, in ascending order.
    public var pendingVersions: [Int] {
        let current = currentVersion ?? 0
        return migrations.keys.filter { $0 > current }.sorted()
    }

    /// Registers a migration step.
    /// - Throws: ``MigrationError/duplicateVersion(_:)`` or ``MigrationError/invalidVersion(_:)``.
    public func register(
        version: Int,
        name: String,
        _ work: @escaping @Sendable () async throws -> Void
    ) throws {
        guard version > 0 else { throw MigrationError.invalidVersion(version) }
        guard migrations[version] == nil else { throw MigrationError.duplicateVersion(version) }
        migrations[version] = Migration(version: version, name: name, work: work)
    }

    /// Applies every pending migration in ascending order.
    ///
    /// The persisted version advances after each successful step. If a step
    /// throws, the run stops and ``MigrationError/stepFailed(version:name:underlying:)``
    /// is thrown; the failing step will be retried on the next call.
    @discardableResult
    public func run() async throws -> Report {
        let starting = currentVersion

        if starting == nil, freshInstallPolicy == .skipAll {
            let latest = latestVersion
            defaults.set(latest, forKey: versionKey)
            return Report(startingVersion: nil, endingVersion: latest,
                          applied: [], skippedForFreshInstall: true)
        }

        var applied: [String] = []
        for version in pendingVersions {
            guard let migration = migrations[version] else { continue }
            do {
                try await migration.work()
            } catch {
                throw MigrationError.stepFailed(
                    version: version, name: migration.name,
                    underlying: String(describing: error))
            }
            defaults.set(version, forKey: versionKey)
            applied.append(migration.name)
        }

        return Report(startingVersion: starting, endingVersion: currentVersion ?? 0,
                      applied: applied, skippedForFreshInstall: false)
    }

    /// Clears the persisted version so every migration is pending again.
    /// Intended for debug menus and tests.
    public func reset() {
        defaults.removeObject(forKey: versionKey)
    }
}
