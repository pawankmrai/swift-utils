# BiometricAuthManager

An async/await wrapper around `LocalAuthentication` for Face ID, Touch ID, Optic ID, and device-passcode authentication. Creates a fresh `LAContext` per attempt (Apple's recommended pattern) and translates loosely-typed `NSError`s into a strongly-typed, `LocalizedError`-conforming error enum.

## API

| Type / Method | Description |
|---|---|
| `BiometricAuthManager.shared` | Shared singleton instance |
| `BiometricAuthManager()` | Create a new independent manager instance |
| `availableBiometryType(policy:)` | Returns the device's `BiometryType` without prompting |
| `canAuthenticate(policy:)` | Returns whether the policy can currently be satisfied, without prompting |
| `authenticate(reason:policy:fallbackTitle:)` | Prompts the user and returns `true` on success (async, throwing) |
| `authenticateWithPasscodeFallback(reason:)` | Convenience for `.biometricsOrPasscode` (async, throwing) |

### BiometryType

| Case | Description |
|---|---|
| `.none` | No biometric hardware available, or not enrolled |
| `.touchID` | Touch ID (fingerprint) is available |
| `.faceID` | Face ID is available |
| `.opticID` | Optic ID is available (Apple Vision Pro) |

### BiometricPolicy

| Case | Description |
|---|---|
| `.biometricsOnly` | Only Face ID / Touch ID / Optic ID satisfy the request |
| `.biometricsOrPasscode` | Biometrics first, with fallback to device passcode / account password |

### BiometricAuthError

| Case | Description |
|---|---|
| `.biometryNotAvailable` | No biometric hardware, or temporarily unavailable |
| `.biometryNotEnrolled` | No biometric data enrolled on the device |
| `.biometryLockedOut` | Too many failed attempts; biometrics locked |
| `.passcodeNotSet` | Device passcode required but not set |
| `.userCancelled` | User tapped Cancel |
| `.userFallback` | User chose the fallback option (e.g. "Enter Password") |
| `.systemCancelled` | System cancelled the request (e.g. app backgrounded) |
| `.authenticationFailed` | Biometric scan did not match a known identity |
| `.other(String)` | Any other underlying failure, with a message |

All cases conform to `LocalizedError` and expose a human-readable `errorDescription`.

## Examples

```swift
import SwiftUtilsHelpers

let biometrics = BiometricAuthManager.shared

// Check what's available before deciding which UI to show
switch biometrics.availableBiometryType() {
case .faceID:
    loginButton.setTitle("Sign in with Face ID", for: .normal)
case .touchID:
    loginButton.setTitle("Sign in with Touch ID", for: .normal)
case .opticID:
    loginButton.setTitle("Sign in with Optic ID", for: .normal)
case .none:
    loginButton.setTitle("Sign in with Passcode", for: .normal)
}

// Simple biometrics-only authentication
func unlockApp() async {
    do {
        let granted = try await biometrics.authenticate(reason: "Unlock to view your account")
        if granted {
            showHome()
        }
    } catch let error as BiometricAuthError {
        switch error {
        case .userCancelled:
            break // user backed out — nothing to show
        case .biometryNotEnrolled, .biometryNotAvailable:
            promptToUsePasscodeInstead()
        default:
            showAlert(message: error.errorDescription ?? "Authentication failed")
        }
    } catch {
        showAlert(message: "Unexpected error")
    }
}

// Allow a passcode fallback for a payment confirmation flow
func confirmPurchase() async throws -> Bool {
    try await biometrics.authenticateWithPasscodeFallback(
        reason: "Confirm purchase of Premium Subscription"
    )
}

// Custom fallback button title, biometrics-only policy
func reauthenticateForSettings() async {
    do {
        let granted = try await biometrics.authenticate(
            reason: "Confirm it's you to change security settings",
            policy: .biometricsOnly,
            fallbackTitle: "Use App PIN"
        )
        guard granted else { return }
        openSecuritySettings()
    } catch {
        print("Re-authentication failed: \(error.localizedDescription)")
    }
}

// Gate a feature behind a capability check, no prompt
func setUpBiometricLoginToggle() {
    biometricToggle.isEnabled = biometrics.canAuthenticate(policy: .biometricsOrPasscode)
}

// SwiftUI usage
struct LockedView: View {
    @State private var isUnlocked = false
    @State private var errorMessage: String?

    var body: some View {
        if isUnlocked {
            SecretContentView()
        } else {
            VStack(spacing: 16) {
                Text("Content Locked")
                Button("Unlock") {
                    Task {
                        do {
                            isUnlocked = try await BiometricAuthManager.shared.authenticate(
                                reason: "Unlock secret content"
                            )
                        } catch {
                            errorMessage = (error as? BiometricAuthError)?.errorDescription
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }
}
```
