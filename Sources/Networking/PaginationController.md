# PaginationController

An actor-based controller that drives incremental page loading for any paged API — page-number, cursor, or opaque-token schemes — while tracking accumulated items, loading state, and errors so view models don't have to.

## API

| Type | Description |
|---|---|
| `Page<Item, Cursor>` | A single page of results: `items` plus the `nextCursor` to fetch more, or `nil` if it's the last page |
| `PaginationController<Item, Cursor>` | Actor that owns the accumulated list, current cursor, and loading/error state |
| `PaginationController.init(fetch:)` | Creates a controller from an async closure `(Cursor?) async throws -> Page<Item, Cursor>` |
| `PaginationController.loadNextPage()` | Fetches and appends the next page; de-dupes concurrent calls; no-ops once `hasMore` is `false` |
| `PaginationController.refresh()` | Resets state and reloads the first page — ideal for pull-to-refresh |
| `PaginationController.reset()` | Clears items, cursor, and error state without fetching |
| `PaginationController.items` | All items accumulated so far, in page order |
| `PaginationController.nextCursor` | The cursor to use for the next fetch, or `nil` |
| `PaginationController.hasMore` | Whether another page is available to fetch |
| `PaginationController.isLoading` | Whether a `loadNextPage()` call is currently in flight |
| `PaginationController.lastError` | The most recent fetch error, cleared on the next successful load |

## Examples

### Page-number pagination

```swift
import SwiftUtilsNetworking

struct Post: Sendable {
    let id: Int
    let title: String
}

let controller = PaginationController<Post, Int> { page in
    let response = try await api.fetchPosts(page: page ?? 1, perPage: 20)
    return Page(
        items: response.posts,
        nextCursor: response.hasMore ? (page ?? 1) + 1 : nil
    )
}

let firstBatch = try await controller.loadNextPage()
```

### Opaque cursor / token pagination

Many APIs return a next-page token instead of a page number — `Cursor` can be any `Sendable` type, including `String`.

```swift
struct FeedItem: Sendable { let id: String; let text: String }

let feed = PaginationController<FeedItem, String> { token in
    let response = try await api.fetchFeed(cursor: token)
    return Page(items: response.items, nextCursor: response.nextPageToken)
}

try await feed.loadNextPage()
```

### Driving a SwiftUI list with infinite scroll

```swift
@MainActor
final class FeedViewModel: ObservableObject {
    @Published var items: [Post] = []
    @Published var isLoading = false

    private let controller = PaginationController<Post, Int> { page in
        let response = try await api.fetchPosts(page: page ?? 1)
        return Page(items: response.posts, nextCursor: response.hasMore ? (page ?? 1) + 1 : nil)
    }

    func loadMoreIfNeeded(currentItem post: Post) async {
        guard post.id == items.last?.id else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await controller.loadNextPage()
            items = await controller.items
        } catch {
            // surface error to the view
        }
    }
}
```

### Pull-to-refresh

```swift
func onPullToRefresh() async {
    let freshFirstPage = try? await controller.refresh()
    items = await controller.items
}
```

### Handling errors without losing progress

A failed fetch leaves `items`, `nextCursor`, and `hasMore` untouched, so the caller can simply retry `loadNextPage()`.

```swift
do {
    try await controller.loadNextPage()
} catch {
    let lastError = await controller.lastError
    print("Failed to load page: \(lastError ?? error)")
    // Retry later — cursor and existing items are preserved.
}
```

### Concurrent call de-duplication

If two callers (e.g. a scroll-triggered load and a manual "Load more" tap) call `loadNextPage()` at nearly the same time, only one network request is made — both callers receive the same page.

```swift
async let a = controller.loadNextPage()
async let b = controller.loadNextPage()
let (pageA, pageB) = try await (a, b) // pageA == pageB, fetched once
```

### Starting over

```swift
await controller.reset() // clears items, cursor, and error — no fetch performed
```
