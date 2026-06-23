# PermissionManager

A unified async/await wrapper for checking and requesting the system permissions an iOS app commonly needs — camera, microphone, photo library, contacts, and location — without juggling four different frameworks' completion-handler or delegate-based APIs.

Each call site must still declare the matching usage-description key in `Info.plist` (e.g. `NSCameraUsageDescription`, `NSContactsUsageDescription`, `NSLocationWhenInUseUsageDescription`); the OS terminates the app if a prompt is triggered without one.

## API

| Type / Method | Description |
|---|---|
| `PermissionManager.shared` | Shared singleton instance |
| `PermissionManager()` | Create a new independent manager instance |
| `status(for:)` | Returns the current `PermissionStatus` for a kind, without prompting |
| `isAuthorized(_:)` | Returns `status(for:).canProceed` as a plain `Bool` |
| `request(_:)` | Requests one permission, prompting only if `.notDetermined` (async) |
| `request(_:)` (array overload) | Requests several permissions in sequence, returns `[PermissionKind: PermissionStatus]` (async) |

### PermissionKind

| Case | Underlying framework |
|---|---|
| `.camera` | `AVCaptureDevice` (`.video`) |
| `.microphone` | `AVCaptureDevice` (`.audio`) |
| `.photoLibrary` | `PHPhotoLibrary` (`.readWrite`) |
| `.photoLibraryAddOnly` | `PHPhotoLibrary` (`.addOnly`) |
| `.contacts` | `CNContactStore` |
| `.locationWhenInUse` | `CLLocationManager` |

### PermissionStatus

| Case | Description |
|---|---|
| `.authorized` | Full access granted |
| `.limited` | Partial access granted (currently only reachable via `.photoLibrary`) |
| `.denied` | The user explicitly denied access |
| `.restricted` | Blocked by a system policy (parental controls, MDM) |
| `.notDetermined` | The user has not yet been asked |

`canProceed` is `true` for `.authorized` and `.limited`, `false` otherwise.

## Examples

```swift
import SwiftUtilsHelpers

let permissions = PermissionManager.shared

// Check before requesting, to drive UI without prompting
if permissions.isAuthorized(.camera) {
    showCameraButton()
}

// Request a single permission
func startScanning() async {
    switch await permissions.request(.camera) {
    case .authorized:
        openCameraSession()
    case .denied, .restricted:
        showOpenSettingsAlert()
    case .limited, .notDetermined:
        break
    }
}

// Onboarding flow requesting several permissions one at a time
func runOnboardingPermissionFlow() async {
    let results = await permissions.request([.camera, .microphone, .photoLibraryAddOnly])

    if results[.camera] == .authorized {
        enableVideoCapture()
    }
    if results[.microphone] == .authorized {
        enableVoiceNotes()
    }
    if results[.photoLibraryAddOnly]?.canProceed == true {
        enableSaveToLibrary()
    }
}

// Location, gated on current status to avoid a redundant prompt
func enableNearbyResults() async {
    guard permissions.status(for: .locationWhenInUse) != .denied else {
        showLocationDeniedMessage()
        return
    }
    let status = await permissions.request(.locationWhenInUse)
    nearbyFeatureEnabled = status.canProceed
}

// Import contacts, handling the result inline
func importContacts() async {
    let status = await permissions.request(.contacts)
    guard status == .authorized else {
        showAlert(message: "Enable Contacts access in Settings to import your address book.")
        return
    }
    runContactImport()
}

// SwiftUI usage
struct CameraGateView: View {
    @State private var status: PermissionStatus = PermissionManager.shared.status(for: .camera)

    var body: some View {
        Group {
            if status.canProceed {
                CameraPreview()
            } else {
                Button("Enable Camera") {
                    Task { status = await PermissionManager.shared.request(.camera) }
                }
            }
        }
    }
}
```
