//
//  BiometricAuthManager.swift
//  SwiftUtils
//
//  An async/await wrapper around LocalAuthentication for Face ID, Touch ID,
//  and device-passcode authentication, with descriptive, typed errors.
//
//  Created by Pawan on 2026-06-22.
//

import LocalAuthentication

// MARK: - BiometryType

/// The kind of biometric authentication available on the current device.
public enum BiometryType: Sendable, Equatable {
    /// No biometric hardware is available, or the device is unenrolled.
    case none
    /// Touch ID (fingerprint) is available.
    case touchID
    /// Face ID is available.
    case faceID
    /// Optic ID is available (Apple Vision Pro).
    case opticID

    fileprivate init(_ laType: LABiometryType) {
        switch laType {
        case .touchID: self = .touchID
        case .faceID: self = .faceID
        case .none: self = .none
        default:
            if #available(iOS 17.0, macOS 14.0, *), laType == .opticID {
                self = .opticID
            } else {
                self = .none
            }
        }
    }
}

// MARK: - BiometricPolicy

/// Determines which authentication methods are acceptable for a request.
public enum BiometricPolicy: Sendable {
    /// Only Face ID / Touch ID / Optic ID may satisfy the request.
    case biometricsOnly
    /// Biometrics are attempted first; the user may fall back to the device
    /// passcode (or, on a Mac, their account password).
    case biometricsOrPasscode

    var laPolicy: LAPolicy {
        switch self {
        case .biometricsOnly: return .deviceOwnerAuthenticationWithBiometrics
        case .biometricsOrPasscode: return .deviceOwnerAuthentication
        }
    }
}

// MARK: - BiometricAuthError

/// A typed, descriptive error surface for biometric authentication failures.
public enum BiometricAuthError: Error, LocalizedError, Equatable {
    /// The device has no biometric hardware, or it is unavailable right now.
    case biometryNotAvailable
    /// The user has not enrolled any biometric data (e.g. no fingerprints/face set up).
    case biometryNotEnrolled
    /// Too many failed attempts; biometrics are temporarily locked out.
    case biometryLockedOut
    /// No device passcode is set, which is required for the requested policy.
    case passcodeNotSet
    /// The user tapped Cancel.
    case userCancelled
    /// The user chose the fallback option (e.g. "Enter Password").
    case userFallback
    /// The system cancelled the request (e.g. app moved to background).
    case systemCancelled
    /// The biometric scan did not match a known identity.
    case authenticationFailed
    /// Any other underlying failure, with a human-readable message.
    case other(String)

    /// Maps a `LocalAuthentication` error into a `BiometricAuthError` case.
    public init(laError: NSError?) {
        guard let laError,
              laError.domain == LAErrorDomain,
              let code = LAError.Code(rawValue: laError.code) else {
            self = .other(laError?.localizedDescription ?? "Unknown authentication error")
            return
        }
        switch code {
        case .biometryNotAvailable: self = .biometryNotAvailable
        case .biometryNotEnrolled: self = .biometryNotEnrolled
        case .biometryLockout: self = .biometryLockedOut
        case .passcodeNotSet: self = .passcodeNotSet
        case .userCancel: self = .userCancelled
        case .userFallback: self = .userFallback
        case .systemCancel, .appCancel: self = .systemCancelled
        case .authenticationFailed: self = .authenticationFailed
        default: self = .other(laError?.localizedDescription ?? "Authentication failed")
        }
    }

    public var errorDescription: String? {
        switch self {
        case .biometryNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometryNotEnrolled:
            return "No biometric data is enrolled. Set up Face ID or Touch ID in Settings."
        case .biometryLockedOut:
            return "Biometric authentication is locked due to too many failed attempts."
        case .passcodeNotSet:
            return "A device passcode is required but has not been set."
        case .userCancelled:
            return "Authentication was cancelled."
        case .userFallback:
            return "The user requested an alternative authentication method."
        case .systemCancelled:
            return "Authentication was cancelled by the system."
        case .authenticationFailed:
            return "Biometric authentication failed to verify identity."
        case .other(let message):
            return message
        }
    }
}

// MARK: - BiometricAuthManager

/// A small, testable wrapper around `LocalAuthentication` that exposes
/// biometric and device-passcode authentication through async/await.
///
/// `BiometricAuthManager` creates a fresh `LAContext` for every authentication
/// attempt (Apple's recommended pattern), and translates the framework's
/// loosely-typed `NSError`s into the strongly-typed `BiometricAuthError`.
///
/// ```swift
/// do {
///     let granted = try await BiometricAuthManager.shared.authenticate(
///         reason: "Unlock your account"
///     )
///     if granted { unlock() }
/// } catch let error as BiometricAuthError {
///     show(error.errorDescription)
/// }
/// ```
public final class BiometricAuthManager: @unchecked Sendable {

    /// Shared singleton instance for convenient access.
    public static let shared = BiometricAuthManager()

    /// Creates a new, independent authentication manager.
    public init() {}

    /// The type of biometric hardware available on this device, without
    /// triggering a prompt.
    ///
    /// - Parameter policy: The policy used to probe availability (default: `.biometricsOnly`).
    /// - Returns: `.none` if no biometric hardware is available or enrolled.
    public func availableBiometryType(policy: BiometricPolicy = .biometricsOnly) -> BiometryType {
        let context = LAContext()
        guard context.canEvaluatePolicy(policy.laPolicy, error: nil) else {
            return .none
        }
        return BiometryType(context.biometryType)
    }

    /// Returns whether the device can currently satisfy the given policy.
    ///
    /// This does not prompt the user — it only checks hardware, enrollment,
    /// and passcode state.
    ///
    /// - Parameter policy: The policy to check (default: `.biometricsOnly`).
    public func canAuthenticate(policy: BiometricPolicy = .biometricsOnly) -> Bool {
        LAContext().canEvaluatePolicy(policy.laPolicy, error: nil)
    }

    /// Prompts the user to authenticate using Face ID, Touch ID, Optic ID,
    /// or (depending on `policy`) the device passcode.
    ///
    /// - Parameters:
    ///   - reason: A short, user-facing explanation of why authentication is needed.
    ///     Shown beneath the Face ID / Touch ID prompt.
    ///   - policy: Which authentication methods are acceptable (default: `.biometricsOnly`).
    ///   - fallbackTitle: A custom title for the fallback button (e.g. "Use PIN").
    ///     Pass `nil` to use the system default, or `""` to hide the fallback button.
    /// - Returns: `true` if authentication succeeded.
    /// - Throws: `BiometricAuthError` describing why authentication could not
    ///   be completed or was denied.
    @discardableResult
    public func authenticate(
        reason: String,
        policy: BiometricPolicy = .biometricsOnly,
        fallbackTitle: String? = nil
    ) async throws -> Bool {
        let context = LAContext()
        if let fallbackTitle {
            context.localizedFallbackTitle = fallbackTitle
        }

        var probeError: NSError?
        guard context.canEvaluatePolicy(policy.laPolicy, error: &probeError) else {
            throw BiometricAuthError(laError: probeError)
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy.laPolicy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: BiometricAuthError(laError: error as NSError?))
                }
            }
        }
    }

    /// Convenience for `authenticate(reason:policy:)` that allows falling
    /// back to the device passcode if biometrics fail or are unavailable.
    ///
    /// - Parameter reason: A short, user-facing explanation shown in the prompt.
    /// - Returns: `true` if authentication succeeded.
    @discardableResult
    public func authenticateWithPasscodeFallback(reason: String) async throws -> Bool {
        try await authenticate(reason: reason, policy: .biometricsOrPasscode)
    }
}
