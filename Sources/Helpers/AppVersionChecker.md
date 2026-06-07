# AppVersionChecker

Fetches the latest App Store version for the running app and compares it with the installed version. Uses the free iTunes Lookup API — no third-party dependencies, no API key required.

## API

| Type / Method / Property | Description |
|---|---|
| `Version(_ string: String)` | Parses a `"major.minor.patch"` string into a comparable value type |
| `Version.description` | Returns the dot-separated string representation |
| `VersionCheckResult.upToDate` | Installed version matches the App Store |
| `VersionCheckResult.updateAvailable(latestVersion:)` | A newer version exists on the store |
| `VersionCheckResult.aheadOfStore` | Installed version is newer (TestFlight / dev build) |
| `AppVersionChecker.shared` | Shared singleton |
| `AppVersionChecker.init(session:)` | Custom initialiser — inject a `URLSession` for testing |
| `AppVersionChecker.installedVersion` | Reads `CFBundleShortVersionString` from the main bundle |
| `AppVersionChecker.check(countryCode:)` | Async — fetches the App Store version and returns a `VersionCheckResult` |
| `AppVersionChecker.latestStoreVersion(countryCode:)` | Async — returns only the latest `Version` without comparing |
| `AppVersionCheckerError` | `bundleIdentifierMissing`, `invalidResponse`, `appNotFoundOnAppStore` |

## Examples

### Basic update check on app launch

```swift
import SwiftUtilsHelpers

func checkForUpdate() async {
    do {
        let result = try await AppVersionChecker.shared.check()
        switch result {
        case .upToDate:
            print("App is up to date.")
        case .updateAvailable(let latest):
            print("Version \(latest) is available — prompt user to update.")
            await showUpdateAlert(latestVersion: latest)
        case .aheadOfStore:
            print("Running a pre-release build.")
        }
    } catch {
        print("Version check failed: \(error.localizedDescription)")
    }
}
```

### Comparing `Version` values directly

```swift
let v1 = Version("1.9.0")!
let v2 = Version("2.0.0")!
let v3 = Version("2.0.0")!

v1 < v2   // true
v2 == v3  // true
v2 > v1   // true

// Sort an array of versions
let versions = ["1.0.0", "2.1.0", "1.5.3"].compactMap(Version.init)
let sorted = versions.sorted()  // [1.0.0, 1.5.3, 2.1.0]
```

### Showing an update alert in SwiftUI

```swift
struct ContentView: View {
    @State private var updateVersion: Version?

    var body: some View {
        NavigationStack {
            // ... main content ...
        }
        .task {
            guard case .updateAvailable(let v) =
                try? await AppVersionChecker.shared.check() else { return }
            updateVersion = v
        }
        .alert(
            "Update Available",
            isPresented: Binding(
                get: { updateVersion != nil },
                set: { if !$0 { updateVersion = nil } }
            )
        ) {
            Button("Update") {
                // Open App Store page
                if let url = URL(string: "https://apps.apple.com/app/idXXXXXXXXX") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Version \(updateVersion?.description ?? "") is available.")
        }
    }
}
```

### Checking the UK App Store

```swift
let result = try await AppVersionChecker.shared.check(countryCode: "gb")
```

### Unit testing with a mock URLSession

```swift
// Inject a custom URLSession configured with URLProtocol stubbing
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let mockSession = URLSession(configuration: config)

let checker = AppVersionChecker(session: mockSession)
let result = try await checker.check()
```
