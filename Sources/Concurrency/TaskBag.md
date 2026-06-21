# TaskBag

A thread-safe container for `Task` handles that cancels everything it holds on `deinit` — the structured-concurrency equivalent of Combine's `Set<AnyCancellable>`.

## API

| Type / Member | Description |
|---|---|
| `TaskBag()` | Creates an empty bag |
| `add<Success>(_ task: Task<Success, Never>)` | Tracks a non-throwing task; auto-removed on completion |
| `add<Success>(_ task: Task<Success, Error>)` | Tracks a throwing task; auto-removed on completion |
| `cancelAll()` | Cancels and removes every tracked task |
| `count` | Number of tasks currently tracked |
| `isEmpty` | Whether the bag is empty |
| `Task.store(in: TaskBag) -> Task` | Adds `self` to a bag and returns it for chaining |

## Examples

```swift
import SwiftUtilsConcurrency

// Basic usage — track a task and let the bag manage its lifecycle
final class SearchViewModel {
    private let tasks = TaskBag()
    @Published var results: [SearchResult] = []

    func search(_ query: String) {
        Task {
            let results = try await api.search(query)
            await MainActor.run { self.results = results }
        }.store(in: tasks)
    }

    // When `SearchViewModel` deinits, any in-flight search is cancelled
    // automatically — no explicit cleanup required.
}
```

```swift
// Cancelling everything on navigation away from a screen
final class FeedViewController: UIViewController {
    private let tasks = TaskBag()

    func loadFeed() {
        Task {
            let posts = try await feedService.fetchPosts()
            await MainActor.run { self.render(posts) }
        }.store(in: tasks)

        Task {
            let ads = try await adsService.fetchAds()
            await MainActor.run { self.renderAds(ads) }
        }.store(in: tasks)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        tasks.cancelAll() // stop both fetches immediately
    }
}
```

```swift
// Tracking multiple tasks without `store(in:)`
let bag = TaskBag()

let downloadTask = Task<Data, Error> {
    try await downloader.fetch(url: imageURL)
}
bag.add(downloadTask)

print(bag.count)   // 1
print(bag.isEmpty) // false

// Completed tasks are removed automatically — no manual bookkeeping needed.
let value = try await downloadTask.value
// shortly after, bag.isEmpty == true
```

```swift
// Throwing tasks work the same way as non-throwing tasks
let bag = TaskBag()

let uploadTask: Task<Void, Error> = Task {
    try await uploader.upload(file: fileURL)
}
uploadTask.store(in: bag)

bag.cancelAll() // cancels the upload; bag is now empty
```

```swift
// Fan-out: track a batch of tasks and cancel them all together
let bag = TaskBag()

for id in pendingIDs {
    Task {
        try await syncEngine.sync(id: id)
    }.store(in: bag)
}

// User cancels the sync operation from the UI
cancelButton.addAction(UIAction { _ in
    bag.cancelAll()
}, for: .touchUpInside)
```
