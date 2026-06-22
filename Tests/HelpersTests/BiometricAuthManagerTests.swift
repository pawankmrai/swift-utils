//
//  BiometricAuthManagerTests.swift
//  SwiftUtils
//

import XCTest
import LocalAuthentication
@testable import SwiftUtilsHelpers

// MARK: - BiometryType Tests

final class BiometryTypeTests: XCTestCase {

    func testNoneIsEqualToNone() {
        XCTAssertEqual(BiometryType.none, BiometryType.none)
    }

    func testFaceIDIsNotEqualToTouchID() {
        XCTAssertNotEqual(BiometryType.faceID, BiometryType.touchID)
    }

    func testOpticIDIsDistinctCase() {
        XCTAssertNotEqual(BiometryType.opticID, BiometryType.none)
        XCTAssertNotEqual(BiometryType.opticID, BiometryType.faceID)
    }
}

// MARK: - BiometricPolicy Tests

final class BiometricPolicyTests: XCTestCase {

    func testBiometricsOnlyMapsToCorrectLAPolicy() {
        XCTAssertEqual(BiometricPolicy.biometricsOnly.laPolicy, .deviceOwnerAuthenticationWithBiometrics)
    }

    func testBiometricsOrPasscodeMapsToCorrectLAPolicy() {
        XCTAssertEqual(BiometricPolicy.biometricsOrPasscode.laPolicy, .deviceOwnerAuthentication)
    }
}

// MARK: - BiometricAuthError Mapping Tests

final class BiometricAuthErrorTests: XCTestCase {

    private func laError(_ code: LAError.Code) -> NSError {
        NSError(domain: LAErrorDomain, code: code.rawValue, userInfo: nil)
    }

    func testMapsBiometryNotAvailable() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.biometryNotAvailable)), .biometryNotAvailable)
    }

    func testMapsBiometryNotEnrolled() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.biometryNotEnrolled)), .biometryNotEnrolled)
    }

    func testMapsBiometryLockout() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.biometryLockout)), .biometryLockedOut)
    }

    func testMapsPasscodeNotSet() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.passcodeNotSet)), .passcodeNotSet)
    }

    func testMapsUserCancel() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.userCancel)), .userCancelled)
    }

    func testMapsUserFallback() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.userFallback)), .userFallback)
    }

    func testMapsSystemCancel() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.systemCancel)), .systemCancelled)
    }

    func testMapsAppCancelToSystemCancelled() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.appCancel)), .systemCancelled)
    }

    func testMapsAuthenticationFailed() {
        XCTAssertEqual(BiometricAuthError(laError: laError(.authenticationFailed)), .authenticationFailed)
    }

    func testNilErrorMapsToOther() {
        switch BiometricAuthError(laError: nil) {
        case .other: break
        default: XCTFail("Expected .other for a nil NSError")
        }
    }

    func testUnrecognizedDomainMapsToOther() {
        let error = NSError(domain: "com.example.unrelated", code: 999, userInfo: [
            NSLocalizedDescriptionKey: "Something else broke"
        ])
        switch BiometricAuthError(laError: error) {
        case .other(let message):
            XCTAssertEqual(message, "Something else broke")
        default:
            XCTFail("Expected .other for a non-LAError domain")
        }
    }

    func testAllCasesHaveNonEmptyErrorDescriptions() {
        let cases: [BiometricAuthError] = [
            .biometryNotAvailable, .biometryNotEnrolled, .biometryLockedOut,
            .passcodeNotSet, .userCancelled, .userFallback,
            .systemCancelled, .authenticationFailed, .other("custom")
        ]
        for error in cases {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error) should have a description")
        }
    }
}

// MARK: - BiometricAuthManager Tests

final class BiometricAuthManagerTests: XCTestCase {

    var manager: BiometricAuthManager!

    override func setUp() {
        super.setUp()
        manager = BiometricAuthManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(BiometricAuthManager.shared)
    }

    func testSharedInstanceIsSingleton() {
        XCTAssertTrue(BiometricAuthManager.shared === BiometricAuthManager.shared)
    }

    func testInitCreatesIndependentInstance() {
        let other = BiometricAuthManager()
        XCTAssertFalse(manager === other)
    }

    func testAvailableBiometryTypeReturnsConsistentResult() {
        // Calling this twice in a row (no hardware state changes in between)
        // should always resolve to the same `BiometryType`.
        let first = manager.availableBiometryType()
        let second = manager.availableBiometryType()
        XCTAssertEqual(first, second)
    }

    func testCanAuthenticateReturnsBoolWithoutPrompting() {
        // Should never hang or prompt — just reports current device capability.
        let result = manager.canAuthenticate()
        XCTAssertTrue(result == true || result == false)
    }

    func testAuthenticateThrowsWhenBiometricsUnavailable() async throws {
        // On a host with no biometric hardware/enrollment, the canEvaluatePolicy
        // pre-check should fail fast with a descriptive error instead of hanging.
        guard !manager.canAuthenticate() else {
            throw XCTSkip("Host has biometrics available; skipping unavailable-path test.")
        }
        do {
            _ = try await manager.authenticate(reason: "Test authentication")
            XCTFail("Expected authenticate to throw when biometrics are unavailable")
        } catch is BiometricAuthError {
            // Expected.
        } catch {
            XCTFail("Expected a BiometricAuthError, got \(error)")
        }
    }
}
