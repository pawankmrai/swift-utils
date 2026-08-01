# LaunchArgumentsParser

Type-safe access to `ProcessInfo` launch arguments and environment variables, for apps that need to change behavior when launched from UI tests or QA/debug builds — skipping onboarding, disabling animations, seeding fixture data, or mocking the current date. Pairs a runtime-side `LaunchArguments` reader with a test-side `LaunchArgumentsBuilder`, so both halves share the same typed flag/option names.

## API

| Type / Method / Property | Description |
|---|---|
| `LaunchFlag` | A named boolean flag, e.g. `-uiTesting` or a truthy env var. `ExpressibleByStringLiteral` |
| `LaunchFlag.uiTesting` / `.resetState` / `.skipOnboarding` / `.disableAnimations` / `.mockNetwork` | Common presets |
| `LaunchOption` | A named `-key value` argument / environment key. `ExpressibleByStringLiteral` |
| `LaunchOption.locale` / `.mockDate` / `.seedFile` | Common presets |
| `LaunchArguments.current` | Static — parses the live `ProcessInfo.processInfo` |
| `LaunchArguments.init(arguments:environment:)` | Creates a parser over explicit values, for unit testing |
| `LaunchArguments.contains(_:)` | `true` if a `LaunchFlag` is present as a bare argument or truthy env var |
| `LaunchArguments.value(for:)` | Raw `String?` for a `LaunchOption` — argument takes precedence over environment |
| `LaunchArguments.typedValue(for:as:)` | Value for a `LaunchOption` converted via `LosslessStringConvertible` (`Int`, `Double`, `Bool`, …) |
| `LaunchArguments.decode(_:for:decoder:)` | Decodes a JSON-string option value into any `Decodable` |
| `LaunchArguments.isRunningUITests` | `true` if `.uiTesting` is set or Xcode's `XCTestConfigurationFilePath` env var is present |
| `LaunchArgumentsBuilder` | Test-side builder for `XCUIApplication.launchArguments` / `.launchEnvironment` |
| `LaunchArgumentsBuilder.flag(_:)` | Adds a bare `-flagName` argument |
| `LaunchArgumentsBuilder.option(_:_:)` | Adds a `-key value` argument pair |
| `LaunchArgumentsBuilder.environment(_:_:)` | Sets a key in the assembled environment dictionary |
| `LaunchArgumentsBuilder.launchArguments` / `.launchEnvironment` | The assembled output |

## Examples

### Reading flags and options at app launch

```swift
import SwiftUtilsHelpers

@main
struct MyApp: App {
    init() {
        let args = LaunchArguments.current

        if args.contains(.disableAnimations) {
            UIView.setAnimationsEnabled(false)
        }
        if args.contains(.resetState) {
            KeychainWrapper.shared.removeAll()
            UserDefaults.standard.dictionaryRepresentation().keys
                .forEach(UserDefaults.standard.removeObject(forKey:))
        }
    }
}
```

### Skipping onboarding and seeding fixture data

```swift
let args = LaunchArguments.current

let shouldSkipOnboarding = args.contains(.skipOnboarding)

struct SeedConfig: Decodable {
    let userCount: Int
    let isPro: Bool
}

if let seed = args.decode(SeedConfig.self, for: .seedFile) {
    FixtureLoader.populate(userCount: seed.userCount, isPro: seed.isPro)
}
```

### Mocking "now" for deterministic UI tests

```swift
let args = LaunchArguments.current

var currentDate: Date {
    if let raw = args.value(for: .mockDate),
       let mocked = ISO8601DateFormatter().date(from: raw) {
        return mocked
    }
    return Date()
}
```

### Reading numeric/boolean options

```swift
// Launched with: -retryLimit 5 -verboseLogging true
let args = LaunchArguments.current
let retryLimit: Int = args.typedValue(for: "retryLimit", as: Int.self) ?? 3
let verbose: Bool = args.typedValue(for: "verboseLogging", as: Bool.self) ?? false
```

### Building launch configuration from a UI test

```swift
import XCTest

final class OnboardingUITests: XCTestCase {
    func testReturningUserSkipsOnboarding() {
        let app = XCUIApplication()
        let config = LaunchArgumentsBuilder()
            .flag(.uiTesting)
            .flag(.skipOnboarding)
            .flag(.disableAnimations)
            .option(.mockDate, "2024-01-01T00:00:00Z")
            .environment(.locale, "en_GB")

        app.launchArguments = config.launchArguments
        app.launchEnvironment = config.launchEnvironment
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
```

### Detecting a test run from shared code

```swift
if LaunchArguments.current.isRunningUITests {
    AnalyticsTracker.shared.isEnabled = false
}
```

### Unit testing app logic without spawning a process

```swift
func testSkipsOnboardingWhenFlagSet() {
    let args = LaunchArguments(arguments: ["-SKIP_ONBOARDING"])
    XCTAssertTrue(args.contains(.skipOnboarding))
}
```
