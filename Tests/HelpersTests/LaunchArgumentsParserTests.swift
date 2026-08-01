import XCTest
@testable import SwiftUtilsHelpers

// MARK: - LaunchFlag / LaunchOption

final class LaunchFlagOptionTests: XCTestCase {

    func testFlagStringLiteralInit() {
        let flag: LaunchFlag = "CUSTOM_FLAG"
        XCTAssertEqual(flag.name, "CUSTOM_FLAG")
        XCTAssertEqual(flag.description, "CUSTOM_FLAG")
    }

    func testOptionStringLiteralInit() {
        let option: LaunchOption = "CUSTOM_OPTION"
        XCTAssertEqual(option.name, "CUSTOM_OPTION")
        XCTAssertEqual(option.description, "CUSTOM_OPTION")
    }

    func testFlagEquality() {
        XCTAssertEqual(LaunchFlag("A"), LaunchFlag("A"))
        XCTAssertNotEqual(LaunchFlag("A"), LaunchFlag("B"))
    }

    func testPresetFlagsAndOptionsHaveExpectedNames() {
        XCTAssertEqual(LaunchFlag.uiTesting.name, "UI_TESTING")
        XCTAssertEqual(LaunchFlag.resetState.name, "RESET_STATE")
        XCTAssertEqual(LaunchFlag.skipOnboarding.name, "SKIP_ONBOARDING")
        XCTAssertEqual(LaunchFlag.disableAnimations.name, "DISABLE_ANIMATIONS")
        XCTAssertEqual(LaunchFlag.mockNetwork.name, "MOCK_NETWORK")
        XCTAssertEqual(LaunchOption.locale.name, "LAUNCH_LOCALE")
        XCTAssertEqual(LaunchOption.mockDate.name, "MOCK_DATE")
        XCTAssertEqual(LaunchOption.seedFile.name, "SEED_FILE")
    }
}

// MARK: - LaunchArguments: Flags

final class LaunchArgumentsFlagTests: XCTestCase {

    func testContainsBareArgumentFlag() {
        let args = LaunchArguments(arguments: ["/path/to/app", "-UI_TESTING"])
        XCTAssertTrue(args.contains(.uiTesting))
    }

    func testDoesNotContainMissingFlag() {
        let args = LaunchArguments(arguments: ["/path/to/app"])
        XCTAssertFalse(args.contains(.uiTesting))
    }

    func testContainsTruthyEnvironmentFlag() {
        for truthy in ["1", "true", "TRUE", "yes", "YES"] {
            let args = LaunchArguments(arguments: [], environment: ["UI_TESTING": truthy])
            XCTAssertTrue(args.contains(.uiTesting), "expected truthy for \(truthy)")
        }
    }

    func testFalsyEnvironmentValueIsNotAFlag() {
        let args = LaunchArguments(arguments: [], environment: ["UI_TESTING": "0"])
        XCTAssertFalse(args.contains(.uiTesting))
    }

    func testFlagPrefixIsStrippedRegardlessOfDashCount() {
        let single = LaunchArguments(arguments: ["-RESET_STATE"])
        let double = LaunchArguments(arguments: ["--RESET_STATE"])
        XCTAssertTrue(single.contains(.resetState))
        XCTAssertTrue(double.contains(.resetState))
    }
}

// MARK: - LaunchArguments: Options

final class LaunchArgumentsOptionTests: XCTestCase {

    func testValueForOptionFromArguments() {
        let args = LaunchArguments(arguments: ["/app", "-MOCK_DATE", "2024-01-01T00:00:00Z"])
        XCTAssertEqual(args.value(for: .mockDate), "2024-01-01T00:00:00Z")
    }

    func testValueForOptionFallsBackToEnvironment() {
        let args = LaunchArguments(arguments: [], environment: ["MOCK_DATE": "2024-06-01T00:00:00Z"])
        XCTAssertEqual(args.value(for: .mockDate), "2024-06-01T00:00:00Z")
    }

    func testArgumentValueTakesPrecedenceOverEnvironment() {
        let args = LaunchArguments(
            arguments: ["-MOCK_DATE", "from-argument"],
            environment: ["MOCK_DATE": "from-environment"]
        )
        XCTAssertEqual(args.value(for: .mockDate), "from-argument")
    }

    func testMissingOptionReturnsNil() {
        let args = LaunchArguments(arguments: [])
        XCTAssertNil(args.value(for: .mockDate))
    }

    func testTypedValueConversion() {
        let args = LaunchArguments(arguments: ["-retryCount", "3", "-ratio", "0.5", "-enabled", "true"])
        XCTAssertEqual(args.typedValue(for: "retryCount", as: Int.self), 3)
        XCTAssertEqual(args.typedValue(for: "ratio", as: Double.self), 0.5)
        XCTAssertEqual(args.typedValue(for: "enabled", as: Bool.self), true)
    }

    func testTypedValueConversionFailureReturnsNil() {
        let args = LaunchArguments(arguments: ["-retryCount", "not-a-number"])
        XCTAssertNil(args.typedValue(for: "retryCount", as: Int.self))
    }

    func testAnArgumentNotFollowedByAValueIsNotParsedAsAnOption() {
        let args = LaunchArguments(arguments: ["-UI_TESTING", "-SKIP_ONBOARDING"])
        XCTAssertNil(args.value(for: "UI_TESTING"))
        XCTAssertTrue(args.contains(.uiTesting))
        XCTAssertTrue(args.contains(.skipOnboarding))
    }
}

// MARK: - LaunchArguments: JSON decoding

private struct SeedConfig: Decodable, Equatable {
    let userCount: Int
    let isPro: Bool
}

final class LaunchArgumentsDecodeTests: XCTestCase {

    func testDecodeValidJSONOption() {
        let args = LaunchArguments(arguments: ["-SEED_FILE", #"{"userCount":3,"isPro":true}"#])
        let config = args.decode(SeedConfig.self, for: .seedFile)
        XCTAssertEqual(config, SeedConfig(userCount: 3, isPro: true))
    }

    func testDecodeMissingOptionReturnsNil() {
        let args = LaunchArguments(arguments: [])
        XCTAssertNil(args.decode(SeedConfig.self, for: .seedFile))
    }

    func testDecodeMalformedJSONReturnsNil() {
        let args = LaunchArguments(arguments: ["-SEED_FILE", "not json"])
        XCTAssertNil(args.decode(SeedConfig.self, for: .seedFile))
    }
}

// MARK: - LaunchArguments: isRunningUITests

final class LaunchArgumentsUITestDetectionTests: XCTestCase {

    func testIsRunningUITestsViaFlag() {
        let args = LaunchArguments(arguments: ["-UI_TESTING"])
        XCTAssertTrue(args.isRunningUITests)
    }

    func testIsRunningUITestsViaXCTestConfigurationEnvironment() {
        let args = LaunchArguments(arguments: [], environment: ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"])
        XCTAssertTrue(args.isRunningUITests)
    }

    func testIsNotRunningUITestsWhenNeitherIsPresent() {
        let args = LaunchArguments(arguments: [], environment: [:])
        XCTAssertFalse(args.isRunningUITests)
    }
}

// MARK: - LaunchArguments.current

final class LaunchArgumentsCurrentTests: XCTestCase {

    func testCurrentReflectsLiveProcessInfo() {
        // The unit test host itself is launched under XCTest, so this should be true
        // via the XCTestConfigurationFilePath environment variable.
        XCTAssertTrue(LaunchArguments.current.isRunningUITests)
    }
}

// MARK: - LaunchArgumentsBuilder

final class LaunchArgumentsBuilderTests: XCTestCase {

    func testBuildsFlagsInOrder() {
        let builder = LaunchArgumentsBuilder()
            .flag(.uiTesting)
            .flag(.skipOnboarding)
        XCTAssertEqual(builder.launchArguments, ["-UI_TESTING", "-SKIP_ONBOARDING"])
    }

    func testBuildsOptionPairs() {
        let builder = LaunchArgumentsBuilder()
            .option(.mockDate, "2024-01-01T00:00:00Z")
        XCTAssertEqual(builder.launchArguments, ["-MOCK_DATE", "2024-01-01T00:00:00Z"])
    }

    func testBuildsEnvironment() {
        let builder = LaunchArgumentsBuilder()
            .environment(.locale, "fr_FR")
        XCTAssertEqual(builder.launchEnvironment, ["LAUNCH_LOCALE": "fr_FR"])
    }

    func testChainingMixesFlagsOptionsAndEnvironment() {
        let builder = LaunchArgumentsBuilder()
            .flag(.uiTesting)
            .option(.mockDate, "2024-01-01T00:00:00Z")
            .environment(.locale, "en_GB")

        XCTAssertEqual(builder.launchArguments, ["-UI_TESTING", "-MOCK_DATE", "2024-01-01T00:00:00Z"])
        XCTAssertEqual(builder.launchEnvironment, ["LAUNCH_LOCALE": "en_GB"])
    }

    func testBuilderOutputRoundTripsThroughLaunchArguments() {
        let builder = LaunchArgumentsBuilder()
            .flag(.uiTesting)
            .option(.mockDate, "2024-01-01T00:00:00Z")
            .environment(.locale, "en_GB")

        let parsed = LaunchArguments(
            arguments: builder.launchArguments,
            environment: builder.launchEnvironment
        )

        XCTAssertTrue(parsed.contains(.uiTesting))
        XCTAssertEqual(parsed.value(for: .mockDate), "2024-01-01T00:00:00Z")
        XCTAssertEqual(parsed.value(for: .locale), "en_GB")
    }
}
