//
//  LocationProvider.swift
//  SwiftUtils
//
//  An async/await and AsyncStream wrapper around CoreLocation for one-shot
//  location fixes and continuous location updates, without delegate
//  boilerplate, Combine, or callback pyramids.
//
//  Created by Pawan on 2026-07-12.
//

import CoreLocation

// MARK: - LocationError

/// Errors surfaced by `LocationProvider`.
public enum LocationError: Error, Sendable, Equatable {
    /// The user has explicitly denied location access.
    case permissionDenied
    /// Location access is blocked by a system policy (parental controls, MDM).
    case permissionRestricted
    /// Location Services are turned off device-wide.
    case locationServicesDisabled
    /// No location fix arrived before the requested timeout elapsed.
    case timedOut
    /// A one-shot `currentLocation()` call was already in flight.
    case requestAlreadyInProgress
    /// CoreLocation reported a failure; the message is `error.localizedDescription`.
    case underlying(String)
}

extension LocationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access was denied. Enable it in Settings to use this feature."
        case .permissionRestricted:
            return "Location access is restricted on this device."
        case .locationServicesDisabled:
            return "Location Services are turned off for this device."
        case .timedOut:
            return "Timed out while waiting for a location fix."
        case .requestAlreadyInProgress:
            return "A location request is already in progress."
        case .underlying(let message):
            return message
        }
    }
}

// MARK: - LocationProvider

/// A single, consistent async/await entry point for one-shot location
/// fetches and continuous location updates, built on `CLLocationManager`.
///
/// ```swift
/// let provider = LocationProvider()
///
/// // One-shot fix, with an authorization prompt if needed.
/// let location = try await provider.currentLocation()
///
/// // Continuous updates, consumed like any other AsyncSequence.
/// for await location in provider.locationUpdates() {
///     updateMapPin(to: location)
/// }
/// ```
///
/// The host app must still declare `NSLocationWhenInUseUsageDescription` in
/// `Info.plist`; the OS terminates the app if a prompt is triggered without it.
public final class LocationProvider: NSObject, @unchecked Sendable {

    /// Tuning knobs for the underlying `CLLocationManager`.
    public struct Configuration: Sendable {
        /// Desired accuracy of reported locations. Defaults to `kCLLocationAccuracyBest`.
        public var desiredAccuracy: CLLocationAccuracy
        /// Minimum distance (meters) a device must move before an update is generated.
        public var distanceFilter: CLLocationDistance
        /// Whether updates may continue while the app is backgrounded (iOS only).
        /// Requires the "Location updates" background mode capability.
        public var allowsBackgroundLocationUpdates: Bool

        public init(
            desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest,
            distanceFilter: CLLocationDistance = kCLDistanceFilterNone,
            allowsBackgroundLocationUpdates: Bool = false
        ) {
            self.desiredAccuracy = desiredAccuracy
            self.distanceFilter = distanceFilter
            self.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
        }

        /// Default configuration: best accuracy, no distance filter, foreground-only.
        public static let `default` = Configuration()
    }

    private let manager: CLLocationManager
    private let lock = NSLock()
    private var pendingOneShot: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var streamContinuation: AsyncStream<CLLocation>.Continuation?
    private var authContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    /// Creates a new provider configured for immediate use.
    public init(configuration: Configuration = .default) {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = configuration.desiredAccuracy
        manager.distanceFilter = configuration.distanceFilter
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = configuration.allowsBackgroundLocationUpdates
        #endif
    }

    /// The current authorization status, read without prompting.
    public var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// Requests when-in-use authorization, prompting only if the status is
    /// `.notDetermined`. If a decision has already been made, that status is
    /// returned immediately with no system prompt.
    @discardableResult
    public func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            lock.lock()
            authContinuations.append(continuation)
            lock.unlock()
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Fetches a single, current location, requesting authorization first if needed.
    ///
    /// Only one one-shot request may be in flight at a time; a second call
    /// made before the first completes throws `.requestAlreadyInProgress`.
    ///
    /// - Parameter timeout: Seconds to wait for a fix before throwing `.timedOut`. Defaults to 15.
    /// - Returns: The most recent `CLLocation` CoreLocation could obtain.
    public func currentLocation(timeout: TimeInterval = 15) async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.locationServicesDisabled
        }

        switch manager.authorizationStatus {
        case .denied:
            throw LocationError.permissionDenied
        case .restricted:
            throw LocationError.permissionRestricted
        case .notDetermined:
            let resolved = await requestWhenInUseAuthorization()
            guard resolved == .authorizedWhenInUse || resolved == .authorizedAlways else {
                throw LocationError.permissionDenied
            }
        default:
            break
        }

        lock.lock()
        guard pendingOneShot == nil else {
            lock.unlock()
            throw LocationError.requestAlreadyInProgress
        }
        lock.unlock()

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingOneShot = continuation
            lock.unlock()

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.completeOneShot(.failure(LocationError.timedOut))
            }
            manager.requestLocation()
        }
    }

    /// A continuous stream of location updates. Starts `CLLocationManager`
    /// updating on subscription and stops it when the stream terminates
    /// (falls out of scope, is cancelled, or `stopLocationUpdates()` is called).
    public func locationUpdates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            lock.lock()
            streamContinuation = continuation
            lock.unlock()
            manager.startUpdatingLocation()

            continuation.onTermination = { [weak self] _ in
                self?.manager.stopUpdatingLocation()
            }
        }
    }

    /// Stops any active continuous updates started via `locationUpdates()`.
    public func stopLocationUpdates() {
        manager.stopUpdatingLocation()
        lock.lock()
        let stream = streamContinuation
        streamContinuation = nil
        lock.unlock()
        stream?.finish()
    }

    private func completeOneShot(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        lock.lock()
        let continuation = pendingOneShot
        pendingOneShot = nil
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case .success(let location): continuation.resume(returning: location)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationProvider: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        lock.lock()
        let continuations = authContinuations
        authContinuations.removeAll()
        lock.unlock()
        let status = manager.authorizationStatus
        continuations.forEach { $0.resume(returning: status) }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        lock.lock()
        let stream = streamContinuation
        let hasPending = pendingOneShot != nil
        lock.unlock()

        stream?.yield(location)
        if hasPending {
            completeOneShot(.success(location))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completeOneShot(.failure(LocationError.underlying(error.localizedDescription)))
    }
}
