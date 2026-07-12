//
//  LocationProviderTests.swift
//  SwiftUtils
//

import XCTest
import CoreLocation
@testable import SwiftUtilsHelpers

// MARK: - LocationError Tests

final class LocationErrorTests: XCTestCase {

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [LocationError] = [
            .permissionDenied,
            .permissionRestricted,
            .locationServicesDisabled,
            .timedOut,
            .requestAlreadyInProgress,
            .underlying("boom"),
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error) should have a description")
        }
    }

    func testUnderlyingCarriesTheOriginalMessage() {
        XCTAssertEqual(LocationError.underlying("boom").errorDescription, "boom")
    }

    func testEquality() {
        XCTAssertEqual(LocationError.timedOut, LocationError.timedOut)
        XCTAssertEqual(LocationError.underlying("x"), LocationError.underlying("x"))
        XCTAssertNotEqual(LocationError.timedOut, LocationError.permissionDenied)
        XCTAssertNotEqual(LocationError.underlying("x"), LocationError.underlying("y"))
    }
}

// MARK: - Configuration Tests

final class LocationProviderConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = LocationProvider.Configuration.default
        XCTAssertEqual(config.desiredAccuracy, kCLLocationAccuracyBest)
        XCTAssertEqual(config.distanceFilter, kCLDistanceFilterNone)
        XCTAssertFalse(config.allowsBackgroundLocationUpdates)
    }

    func testCustomConfiguration() {
        let config = LocationProvider.Configuration(
            desiredAccuracy: kCLLocationAccuracyHundredMeters,
            distanceFilter: 50,
            allowsBackgroundLocationUpdates: true
        )
        XCTAssertEqual(config.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        XCTAssertEqual(config.distanceFilter, 50)
        XCTAssertTrue(config.allowsBackgroundLocationUpdates)
    }
}

// MARK: - LocationProvider Tests

final class LocationProviderTests: XCTestCase {

    var provider: LocationProvider!

    override func setUp() {
        super.setUp()
        provider = LocationProvider()
    }

    override func tearDown() {
        provider.stopLocationUpdates()
        provider = nil
        super.tearDown()
    }

    func testInitDoesNotCrashAndExposesAValidStatus() {
        let validCases: [CLAuthorizationStatus] = [
            .notDetermined, .restricted, .denied, .authorizedAlways, .authorizedWhenInUse,
        ]
        XCTAssertTrue(validCases.contains(provider.authorizationStatus))
    }

    func testAuthorizationStatusIsStableAcrossRepeatedReads() {
        XCTAssertEqual(provider.authorizationStatus, provider.authorizationStatus)
    }

    /// Reading status never prompts, so this must never hang even on a
    /// headless CI runner with no Info.plist usage-description key.
    func testRequestWhenInUseAuthorizationDoesNotPromptWhenAlreadyDetermined() async throws {
        guard provider.authorizationStatus != .notDetermined else {
            throw XCTSkip("Host status is undetermined; requesting would trigger a live system prompt.")
        }
        let result = await provider.requestWhenInUseAuthorization()
        XCTAssertEqual(result, provider.authorizationStatus)
    }

    func testCurrentLocationThrowsPermissionDeniedWhenDenied() async throws {
        guard provider.authorizationStatus == .denied else {
            throw XCTSkip("Host authorization status is not .denied; skipping to avoid depending on system state.")
        }
        do {
            _ = try await provider.currentLocation()
            XCTFail("Expected LocationError.permissionDenied")
        } catch let error as LocationError {
            XCTAssertEqual(error, .permissionDenied)
        }
    }

    func testCurrentLocationThrowsRestrictedWhenRestricted() async throws {
        guard provider.authorizationStatus == .restricted else {
            throw XCTSkip("Host authorization status is not .restricted; skipping to avoid depending on system state.")
        }
        do {
            _ = try await provider.currentLocation()
            XCTFail("Expected LocationError.permissionRestricted")
        } catch let error as LocationError {
            XCTAssertEqual(error, .permissionRestricted)
        }
    }

    /// `locationUpdates()` must be safe to start and immediately stop
    /// without hanging, even with no hardware location fix available.
    func testLocationUpdatesStreamTerminatesAfterStop() {
        let stream = provider.locationUpdates()
        provider.stopLocationUpdates()

        let expectation = expectation(description: "stream terminates")
        Task {
            for await _ in stream {
                // No fixes are expected in a CI environment; we only care
                // that the loop exits once the stream finishes.
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testStopLocationUpdatesIsSafeToCallWithoutAnActiveStream() {
        // Should be a no-op, not a crash, when no stream has been started.
        provider.stopLocationUpdates()
    }
}
