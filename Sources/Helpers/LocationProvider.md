# LocationProvider

An async/await and `AsyncStream` wrapper around `CoreLocation` for one-shot location fixes and continuous location updates — no delegate boilerplate, no Combine, no callback pyramids.

The host app must still declare `NSLocationWhenInUseUsageDescription` in `Info.plist`; the OS terminates the app if a prompt is triggered without it.

## API

| Type / Method | Description |
|---|---|
| `LocationProvider(configuration:)` | Creates a provider, ready to use immediately |
| `authorizationStatus` | Current `CLAuthorizationStatus`, read without prompting |
| `requestWhenInUseAuthorization()` | Requests when-in-use access, prompting only if `.notDetermined` (async) |
| `currentLocation(timeout:)` | Fetches one location fix, requesting authorization first if needed (async, throws) |
| `locationUpdates()` | Returns an `AsyncStream<CLLocation>` of continuous updates |
| `stopLocationUpdates()` | Stops any active stream from `locationUpdates()` |

### Configuration

| Property | Description |
|---|---|
| `desiredAccuracy` | Passed straight to `CLLocationManager.desiredAccuracy`. Defaults to `kCLLocationAccuracyBest` |
| `distanceFilter` | Minimum movement (meters) before a new update fires. Defaults to `kCLDistanceFilterNone` |
| `allowsBackgroundLocationUpdates` | Whether updates continue while backgrounded (iOS only; requires the "Location updates" background mode). Defaults to `false` |

### LocationError

| Case | Meaning |
|---|---|
| `.permissionDenied` | The user explicitly denied location access |
| `.permissionRestricted` | Blocked by a system policy (parental controls, MDM) |
| `.locationServicesDisabled` | Location Services are off device-wide |
| `.timedOut` | No fix arrived before the requested timeout |
| `.requestAlreadyInProgress` | A second `currentLocation()` call was made while one was already in flight |
| `.underlying(String)` | CoreLocation reported a failure; carries `error.localizedDescription` |

`LocationError` conforms to `LocalizedError`, so `error.localizedDescription` reads naturally in UI alerts.

## Examples

```swift
import SwiftUtilsHelpers
import CoreLocation

let locationProvider = LocationProvider()
```

### One-shot fix

```swift
func showNearbyResults() async {
    do {
        let location = try await locationProvider.currentLocation(timeout: 10)
        loadResults(near: location.coordinate)
    } catch LocationError.permissionDenied, LocationError.permissionRestricted {
        showEnableLocationInSettingsAlert()
    } catch LocationError.locationServicesDisabled {
        showTurnOnLocationServicesAlert()
    } catch {
        showAlert(message: error.localizedDescription)
    }
}
```

### Continuous updates

```swift
final class TripTracker {
    private let provider = LocationProvider(
        configuration: .init(desiredAccuracy: kCLLocationAccuracyBest, distanceFilter: 10)
    )
    private var trackingTask: Task<Void, Never>?

    func startTracking() {
        trackingTask = Task {
            for await location in provider.locationUpdates() {
                appendToRoute(location)
            }
        }
    }

    func stopTracking() {
        trackingTask?.cancel()
        provider.stopLocationUpdates()
    }
}
```

### Custom configuration for background tracking

```swift
let config = LocationProvider.Configuration(
    desiredAccuracy: kCLLocationAccuracyHundredMeters,
    distanceFilter: 100,
    allowsBackgroundLocationUpdates: true
)
let backgroundProvider = LocationProvider(configuration: config)
```

### Checking authorization before showing UI

```swift
struct NearMeButton: View {
    @State private var status = LocationProvider().authorizationStatus

    var body: some View {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            Button("Find Nearby") { Task { await findNearby() } }
        } else {
            Button("Enable Location") {
                Task { status = await LocationProvider().requestWhenInUseAuthorization() }
            }
        }
    }
}
```

### Guarding against overlapping one-shot requests

```swift
do {
    let location = try await locationProvider.currentLocation()
    tagPhoto(with: location)
} catch LocationError.requestAlreadyInProgress {
    // A previous currentLocation() call hasn't resolved yet — ignore the tap.
} catch {
    showAlert(message: error.localizedDescription)
}
```
