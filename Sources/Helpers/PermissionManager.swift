//
//  PermissionManager.swift
//  SwiftUtils
//
//  A unified async/await wrapper for requesting and checking iOS system
//  permissions — camera, microphone, photo library, contacts, and
//  location — without juggling each framework's own completion-handler
//  or delegate-based API.
//
//  Created by Pawan on 2026-06-23.
//

import AVFoundation
import Contacts
import CoreLocation
import Photos

// MARK: - PermissionKind

/// A system capability that requires user authorization before use.
public enum PermissionKind: Sendable, Hashable, CaseIterable {
    /// Access to the camera, via `AVCaptureDevice`.
    case camera
    /// Access to the microphone, via `AVCaptureDevice`.
    case microphone
    /// Full read/write access to the photo library, via `PHPhotoLibrary`.
    case photoLibrary
    /// "Add only" access to the photo library — save without browsing existing photos.
    case photoLibraryAddOnly
    /// Access to the user's contacts, via `CNContactStore`.
    case contacts
    /// Location access while the app is in use, via `CLLocationManager`.
    case locationWhenInUse
}

// MARK: - PermissionStatus

/// The current authorization state for a `PermissionKind`, normalized
/// across the four underlying frameworks into one common shape.
public enum PermissionStatus: Sendable, Equatable {
    /// Full access has been granted.
    case authorized
    /// Partial access has been granted (currently only possible for `.photoLibrary`).
    case limited
    /// The user explicitly denied access.
    case denied
    /// Access is restricted by a system policy (e.g. parental controls, MDM).
    case restricted
    /// The user has not yet been asked.
    case notDetermined

    /// `true` for `.authorized` and `.limited` — i.e. the feature can be used at all.
    public var canProceed: Bool {
        self == .authorized || self == .limited
    }

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    init(_ status: CNAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }
}

// MARK: - PermissionManager

/// A single, consistent async/await entry point for checking and requesting
/// the system permissions an app commonly needs.
///
/// `PermissionManager` reads each framework's current authorization status
/// without prompting via `status(for:)`, and requests access — prompting
/// only when the status is `.notDetermined` — via `request(_:)`.
///
/// Each call site must still declare the matching usage-description key in
/// `Info.plist` (e.g. `NSCameraUsageDescription`); the OS terminates the app
/// if a prompt is triggered without one.
///
/// ```swift
/// let permissions = PermissionManager.shared
///
/// switch await permissions.request(.camera) {
/// case .authorized:
///     startCameraSession()
/// case .denied, .restricted:
///     showSettingsPrompt()
/// default:
///     break
/// }
/// ```
public final class PermissionManager: @unchecked Sendable {

    /// Shared singleton instance for convenient access.
    public static let shared = PermissionManager()

    /// Creates a new, independent permission manager.
    public init() {}

    /// Returns the current authorization status for `kind` without prompting the user.
    ///
    /// - Parameter kind: The capability to check.
    /// - Returns: The current `PermissionStatus`, read directly from the owning framework.
    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .camera:
            return PermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return PermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        case .photoLibrary:
            return PermissionStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .photoLibraryAddOnly:
            return PermissionStatus(PHPhotoLibrary.authorizationStatus(for: .addOnly))
        case .contacts:
            return PermissionStatus(CNContactStore.authorizationStatus(for: .contacts))
        case .locationWhenInUse:
            return PermissionStatus(CLLocationManager().authorizationStatus)
        }
    }

    /// Convenience for `status(for:).canProceed`.
    ///
    /// - Parameter kind: The capability to check.
    /// - Returns: `true` if the feature can be used right now without a further prompt.
    public func isAuthorized(_ kind: PermissionKind) -> Bool {
        status(for: kind).canProceed
    }

    /// Requests access to `kind`, prompting the user only if the current
    /// status is `.notDetermined`. If the status has already been decided
    /// (granted, denied, or restricted), the existing status is returned
    /// immediately with no system prompt.
    ///
    /// - Parameter kind: The capability to request.
    /// - Returns: The resulting `PermissionStatus` once the request completes.
    @discardableResult
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied

        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .authorized : .denied

        case .photoLibrary:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return PermissionStatus(status)

        case .photoLibraryAddOnly:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return PermissionStatus(status)

        case .contacts:
            return await requestContactsAccess()

        case .locationWhenInUse:
            return await requestLocationWhenInUse()
        }
    }

    /// Requests several permissions in sequence, one prompt at a time.
    ///
    /// Useful for an onboarding screen that needs to walk the user through
    /// a handful of permissions without overlapping system prompts.
    ///
    /// - Parameter kinds: The capabilities to request, in order.
    /// - Returns: A dictionary mapping each requested kind to its resulting status.
    @discardableResult
    public func request(_ kinds: [PermissionKind]) async -> [PermissionKind: PermissionStatus] {
        var results: [PermissionKind: PermissionStatus] = [:]
        for kind in kinds {
            results[kind] = await request(kind)
        }
        return results
    }

    // MARK: - Contacts

    private func requestContactsAccess() async -> PermissionStatus {
        do {
            let granted = try await CNContactStore().requestAccess(for: .contacts)
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    // MARK: - Location

    private func requestLocationWhenInUse() async -> PermissionStatus {
        let manager = CLLocationManager()
        let current = PermissionStatus(manager.authorizationStatus)
        guard current == .notDetermined else {
            // `requestWhenInUseAuthorization()` is a no-op once a decision has
            // already been made, so the delegate would never fire again —
            // short-circuit here instead of awaiting forever.
            return current
        }
        return await LocationAuthorizationRequest(manager: manager).requestWhenInUse()
    }
}

// MARK: - LocationAuthorizationRequest

/// A one-shot `CLLocationManagerDelegate` that bridges the delegate-based
/// authorization callback into a single `async` call. A fresh instance is
/// created per request and kept alive for the lifetime of that request via
/// the suspended call frame itself.
private final class LocationAuthorizationRequest: NSObject, CLLocationManagerDelegate {

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<PermissionStatus, Never>?

    init(manager: CLLocationManager) {
        self.manager = manager
        super.init()
    }

    func requestWhenInUse() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: PermissionStatus(manager.authorizationStatus))
    }
}
