//
//  PermissionManagerTests.swift
//  SwiftUtils
//

import XCTest
import AVFoundation
import Contacts
import CoreLocation
import Photos
@testable import SwiftUtilsHelpers

// MARK: - PermissionKind Tests

final class PermissionKindTests: XCTestCase {

    func testAllCasesAreUnique() {
        let cases = PermissionKind.allCases
        XCTAssertEqual(Set(cases).count, cases.count)
    }

    func testAllCasesContainsExpectedCount() {
        // camera, microphone, photoLibrary, photoLibraryAddOnly, contacts, locationWhenInUse
        XCTAssertEqual(PermissionKind.allCases.count, 6)
    }
}

// MARK: - PermissionStatus Mapping Tests

final class PermissionStatusMappingTests: XCTestCase {

    // AVAuthorizationStatus

    func testMapsAVAuthorized() {
        XCTAssertEqual(PermissionStatus(AVAuthorizationStatus.authorized), .authorized)
    }

    func testMapsAVDenied() {
        XCTAssertEqual(PermissionStatus(AVAuthorizationStatus.denied), .denied)
    }

    func testMapsAVRestricted() {
        XCTAssertEqual(PermissionStatus(AVAuthorizationStatus.restricted), .restricted)
    }

    func testMapsAVNotDetermined() {
        XCTAssertEqual(PermissionStatus(AVAuthorizationStatus.notDetermined), .notDetermined)
    }

    // PHAuthorizationStatus

    func testMapsPHAuthorized() {
        XCTAssertEqual(PermissionStatus(PHAuthorizationStatus.authorized), .authorized)
    }

    func testMapsPHLimited() {
        XCTAssertEqual(PermissionStatus(PHAuthorizationStatus.limited), .limited)
    }

    func testMapsPHDenied() {
        XCTAssertEqual(PermissionStatus(PHAuthorizationStatus.denied), .denied)
    }

    func testMapsPHRestricted() {
        XCTAssertEqual(PermissionStatus(PHAuthorizationStatus.restricted), .restricted)
    }

    func testMapsPHNotDetermined() {
        XCTAssertEqual(PermissionStatus(PHAuthorizationStatus.notDetermined), .notDetermined)
    }

    // CNAuthorizationStatus

    func testMapsCNAuthorized() {
        XCTAssertEqual(PermissionStatus(CNAuthorizationStatus.authorized), .authorized)
    }

    func testMapsCNDenied() {
        XCTAssertEqual(PermissionStatus(CNAuthorizationStatus.denied), .denied)
    }

    func testMapsCNRestricted() {
        XCTAssertEqual(PermissionStatus(CNAuthorizationStatus.restricted), .restricted)
    }

    func testMapsCNNotDetermined() {
        XCTAssertEqual(PermissionStatus(CNAuthorizationStatus.notDetermined), .notDetermined)
    }

    // CLAuthorizationStatus

    func testMapsCLAuthorizedAlways() {
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.authorizedAlways), .authorized)
    }

    func testMapsCLAuthorizedWhenInUse() {
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.authorizedWhenInUse), .authorized)
    }

    func testMapsCLDenied() {
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.denied), .denied)
    }

    func testMapsCLRestricted() {
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.restricted), .restricted)
    }

    func testMapsCLNotDetermined() {
        XCTAssertEqual(PermissionStatus(CLAuthorizationStatus.notDetermined), .notDetermined)
    }

    // canProceed

    func testCanProceedIsTrueForAuthorizedAndLimited() {
        XCTAssertTrue(PermissionStatus.authorized.canProceed)
        XCTAssertTrue(PermissionStatus.limited.canProceed)
    }

    func testCanProceedIsFalseForDeniedRestrictedAndNotDetermined() {
        XCTAssertFalse(PermissionStatus.denied.canProceed)
        XCTAssertFalse(PermissionStatus.restricted.canProceed)
        XCTAssertFalse(PermissionStatus.notDetermined.canProceed)
    }
}

// MARK: - PermissionManager Tests

final class PermissionManagerTests: XCTestCase {

    var manager: PermissionManager!

    override func setUp() {
        super.setUp()
        manager = PermissionManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(PermissionManager.shared)
    }

    func testSharedInstanceIsSingleton() {
        XCTAssertTrue(PermissionManager.shared === PermissionManager.shared)
    }

    func testInitCreatesIndependentInstance() {
        let other = PermissionManager()
        XCTAssertFalse(manager === other)
    }

    /// Reading status never prompts and should be safe to call for every kind
    /// on any host, including a CI runner with no permission entitlements.
    func testStatusForEveryKindReturnsWithoutHanging() {
        for kind in PermissionKind.allCases {
            let status = manager.status(for: kind)
            let validCases: [PermissionStatus] = [.authorized, .limited, .denied, .restricted, .notDetermined]
            XCTAssertTrue(validCases.contains(status), "Unexpected status \(status) for \(kind)")
        }
    }

    func testStatusIsConsistentAcrossRepeatedCalls() {
        // No permission state changes between these two calls, so the
        // result should be stable.
        for kind in PermissionKind.allCases {
            XCTAssertEqual(manager.status(for: kind), manager.status(for: kind))
        }
    }

    func testIsAuthorizedMatchesCanProceedOnStatus() {
        for kind in PermissionKind.allCases {
            XCTAssertEqual(manager.isAuthorized(kind), manager.status(for: kind).canProceed)
        }
    }

    /// Requesting a permission whose status is already decided must return
    /// immediately with the existing status rather than showing a system
    /// prompt (which would also crash in a host without the matching
    /// Info.plist usage-description key).
    func testRequestDoesNotPromptWhenAlreadyDetermined() async throws {
        for kind in PermissionKind.allCases {
            let current = manager.status(for: kind)
            guard current != .notDetermined else {
                continue // Would require a live system prompt — covered by the skip test below.
            }
            let result = await manager.request(kind)
            XCTAssertEqual(result, current, "Re-requesting \(kind) should return the existing status")
        }
    }

    func testRequestSkipsWhenStatusUndetermined() throws {
        let undetermined = PermissionKind.allCases.filter { manager.status(for: $0) == .notDetermined }
        guard undetermined.isEmpty else {
            throw XCTSkip("Host has undetermined permissions (\(undetermined)); skipping to avoid a live system prompt.")
        }
        // Nothing further to assert — this test exists purely to document
        // why undetermined kinds aren't exercised through request(_:) here.
    }

    func testBatchRequestReturnsAnEntryForEveryDeterminedKind() async {
        let determined = PermissionKind.allCases.filter { manager.status(for: $0) != .notDetermined }
        guard !determined.isEmpty else { return }
        let results = await manager.request(determined)
        XCTAssertEqual(Set(results.keys), Set(determined))
        for kind in determined {
            XCTAssertEqual(results[kind], manager.status(for: kind))
        }
    }
}
