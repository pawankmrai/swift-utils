# MigrationRunner

An actor that runs versioned, one-time data migrations exactly once per install — schema-style migrations for your app's local state.

Every app eventually needs "run this once after the user upgrades" logic: rename a `UserDefaults` key, move files out of `Caches`, re-encode a stored model, purge a legacy Keychain item. Scattering `didMigrateX` flags around the codebase gets messy fast. `MigrationRunner` replaces them with an ordered list of numbered steps and a single persisted schema version. Steps run in ascending order, only once, and the version is committed after **each** successful step — so a failure halfway through resumes cleanly on the next launch.

## API

| Type / Method | Description |
|---|---|
| `MigrationRunner(defaults:versionKey:freshInstallPolicy:)` | Creates a runner that persists the applied version in `UserDefaults` |
| `register(version:name:_:)` | Registers a numbered migration step; throws on duplicate or non-positive versions |
| `run() -> Report` | Applies all pending migrations in ascending order, committing the version after each step |
| `currentVersion: Int?` | Last successfully applied version (`nil` on a fresh install) |
| `latestVersion: Int` | Highest registered version |
| `pendingVersions: [Int]` | Registered versions not yet applied, sorted ascending |
| `reset()` | Clears the persisted version (debug menus / tests) |
| `FreshInstallPolicy` | `.runAll` (default) or `.skipAll` — what to do when no version was ever stored |
| `Report` | `startingVersion`, `endingVersion`, `applied` step names, `skippedForFreshInstall` |
| `MigrationError` | `.duplicateVersion`, `.invalidVersion`, `.stepFailed(version:name:underlying:)` |

## Examples

### Basic setup at launch

```swift
import SwiftUtilsStorage

@main
struct MyApp: App {
    init() {
        Task { await AppMigrations.run() }
    }
    var body: some Scene { WindowGroup { ContentView() } }
}

enum AppMigrations {
    static let runner = MigrationRunner()

    static func run() async {
        do {
            try await runner.register(version: 1, name: "Rename theme key") {
                let d = UserDefaults.standard
                if let theme = d.string(forKey: "theme") {
                    d.set(theme, forKey: "appearance.theme")
                    d.removeObject(forKey: "theme")
                }
            }
            try await runner.register(version: 2, name: "Move downloads to Application Support") {
                try FileMigrations.moveDownloadsOutOfCaches()
            }

            let report = try await runner.run()
            print("Migrations applied: \(report.applied)")
        } catch {
            print("Migration failed: \(error)")
        }
    }
}
```

### Skip migrations on a fresh install

New users have no legacy data, so there's nothing to migrate. Mark everything as applied instead:

```swift
let runner = MigrationRunner(freshInstallPolicy: .skipAll)
try await runner.register(version: 1, name: "Convert legacy favorites") { /* ... */ }
try await runner.register(version: 2, name: "Purge old token") { /* ... */ }

let report = try await runner.run()
// Fresh install  → report.skippedForFreshInstall == true, version set to 2
// Existing user  → pending steps run normally
```

> Tip: if your app shipped before adopting `MigrationRunner`, `.skipAll` can't tell an old user from a new one. Seed the version yourself for existing users (e.g. if a known legacy key exists, `UserDefaults.standard.set(0, forKey: "swiftutils.migrations.version")`) before calling `run()`.

### Re-encoding a stored Codable model

```swift
struct ProfileV1: Codable { let fullName: String }
struct ProfileV2: Codable { let firstName: String; let lastName: String }

try await runner.register(version: 3, name: "Split profile name") {
    let d = UserDefaults.standard
    guard let data = d.data(forKey: "profile"),
          let old = try? JSONDecoder().decode(ProfileV1.self, from: data) else { return }

    let parts = old.fullName.split(separator: " ", maxSplits: 1).map(String.init)
    let new = ProfileV2(firstName: parts.first ?? "", lastName: parts.dropFirst().first ?? "")
    d.set(try JSONEncoder().encode(new), forKey: "profile")
}
```

### Handling a failed step

```swift
do {
    try await runner.run()
} catch MigrationRunner.MigrationError.stepFailed(let version, let name, let underlying) {
    Logger.shared.error("Migration \(version) '\(name)' failed: \(underlying)")
    // Steps before `version` are committed; this one retries next launch.
}
```

### Inspecting state for a debug menu

```swift
let current = await runner.currentVersion      // e.g. 2
let latest  = await runner.latestVersion       // e.g. 3
let pending = await runner.pendingVersions     // [3]

Button("Re-run all migrations") {
    Task {
        await runner.reset()
        try await runner.run()
    }
}
```

### Isolated runners per feature

Use separate keys so modules can version their own data independently:

```swift
let chatMigrations  = MigrationRunner(versionKey: "chat.migrations.version")
let mediaMigrations = MigrationRunner(versionKey: "media.migrations.version")
```

### Testing with an isolated UserDefaults suite

```swift
let suite = "MigrationTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let runner = MigrationRunner(defaults: defaults)
// ... register & run ...
defaults.removePersistentDomain(forName: suite)
```

## Notes

- Keep migration steps **idempotent** where possible — if the app is killed mid-step, that step runs again next launch.
- Never renumber or remove a shipped migration; only append new, higher versions.
- Migrations run sequentially on the actor; long-running work (e.g. large file moves) should be kept off the launch-critical path.
