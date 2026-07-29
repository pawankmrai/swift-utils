# BackgroundTaskManager

A thread-safe wrapper around `BGTaskScheduler` that removes the boilerplate of registering, scheduling, and handling iOS background tasks (app refresh and processing tasks), and keeps a small in-memory log of recent runs for diagnostics.

## API

| Type / Method / Property | Description |
|---|---|
| `BackgroundTaskManager.shared` | Shared, app-wide singleton |
| `BackgroundTaskManager.init(maxRecords:)` | Creates a manager, optionally isolated for testing |
| `BackgroundTaskManager.TaskKind.appRefresh` | Short, periodic refresh task |
| `BackgroundTaskManager.TaskKind.processing(requiresNetwork:requiresExternalPower:)` | Longer-running maintenance/pre-fetch task |
| `register(identifier:kind:handler:)` | Registers an async handler for a task identifier; call before app launch finishes |
| `scheduleAppRefresh(identifier:earliestBeginDate:)` | Submits a `BGAppRefreshTaskRequest` |
| `scheduleProcessing(identifier:earliestBeginDate:requiresNetwork:requiresExternalPower:)` | Submits a `BGProcessingTaskRequest` |
| `cancel(identifier:)` | Cancels a pending request for one identifier |
| `cancelAll()` | Cancels every pending request submitted by the app |
| `recentRuns` | Most recent `RunRecord`s, newest first, capped at `maxRecords` |
| `lastRun(for:)` | The most recent `RunRecord` for a given identifier |
| `RunRecord` | `identifier`, `startedAt`, `finishedAt`, `succeeded`, `expired`, `duration` |
| `SchedulingError` | `backgroundTasksUnavailable`, `underlying(Error)` |

## Examples

### Registering a refresh task at launch

```swift
import SwiftUtilsHelpers
import BackgroundTasks

func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    BackgroundTaskManager.shared.register(
        identifier: "com.myapp.refresh",
        kind: .appRefresh
    ) { _ in
        await SyncService.shared.syncLatestData()
        return true
    }
    return true
}
```

Add the identifier to `Info.plist`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.myapp.refresh</string>
</array>
```

### Scheduling the next run

```swift
func sceneDidEnterBackground(_ scene: UIScene) {
    try? BackgroundTaskManager.shared.scheduleAppRefresh(
        identifier: "com.myapp.refresh",
        earliestBeginDate: Date().addingTimeInterval(15 * 60)
    )
}
```

### Registering a longer processing task

```swift
BackgroundTaskManager.shared.register(
    identifier: "com.myapp.database-cleanup",
    kind: .processing(requiresNetwork: false, requiresExternalPower: true)
) { _ in
    await DatabaseMaintenance.pruneOldRecords()
    return true
}

try? BackgroundTaskManager.shared.scheduleProcessing(
    identifier: "com.myapp.database-cleanup",
    earliestBeginDate: Date().addingTimeInterval(60 * 60 * 24),
    requiresExternalPower: true
)
```

### Inspecting recent runs for diagnostics

```swift
if let last = BackgroundTaskManager.shared.lastRun(for: "com.myapp.refresh") {
    print("Last refresh ran for \(last.duration)s, succeeded: \(last.succeeded)")
}

for run in BackgroundTaskManager.shared.recentRuns {
    print("\(run.identifier): \(run.succeeded ? "OK" : "failed") in \(run.duration)s")
}
```

### Cancelling scheduled work

```swift
// Cancel one identifier, e.g. when a feature is disabled
BackgroundTaskManager.shared.cancel(identifier: "com.myapp.database-cleanup")

// Cancel everything, e.g. on sign-out
BackgroundTaskManager.shared.cancelAll()
```

### Handling expiration gracefully

The system can end a background task early if it runs too long. Structure your handler's work as a cancellable `Task` and check `Task.isCancelled` at safe points — `BackgroundTaskManager` cancels the underlying work automatically when `expirationHandler` fires and logs the run as `expired: true`:

```swift
BackgroundTaskManager.shared.register(identifier: "com.myapp.refresh", kind: .appRefresh) { _ in
    for batch in await SyncService.shared.pendingBatches() {
        if Task.isCancelled { return false }
        await SyncService.shared.upload(batch)
    }
    return true
}
```
