# ConcurrentMap

`TaskGroup`-backed concurrent transforms for sequences, plus a first-to-finish race helper. The parallel counterparts to `map`, `forEach`, and `compactMap` — fan async work out across a sequence (optionally capped at a concurrency limit) and get results back in input order.

Use it to batch-fetch details for a list of IDs, resize a folder of images in parallel, or race redundant data sources against each other.

## API

| Type / Method | Description |
|---|---|
| `Sequence.concurrentMap(maxConcurrency:_:) async throws -> [T]` | Transform every element concurrently; results preserve input order |
| `Sequence.concurrentForEach(maxConcurrency:_:) async throws` | Run an async operation per element concurrently, discarding results |
| `Sequence.concurrentCompactMap(maxConcurrency:_:) async throws -> [T]` | Concurrent transform that drops `nil` results, async `compactMap` |
| `ConcurrentRace.firstSuccess(_:) async throws -> T` | Race async operations; returns the first successful result, cancels the rest |
| `ConcurrentRaceError.noOperations` | Thrown by `firstSuccess` when given an empty operations array |

`maxConcurrency` defaults to `nil` (unbounded — every element starts immediately). Pass a positive `Int` to cap how many transforms run at once.

## Examples

### Batch-fetch details for a list of IDs

```swift
let userIDs = [101, 102, 103, 104, 105]

let users = try await userIDs.concurrentMap { id in
    try await api.fetchUser(id: id)
}
// users[i] corresponds to userIDs[i], regardless of network timing.
```

### Cap concurrency to avoid overwhelming a server

```swift
let imageURLs: [URL] = post.attachmentURLs

let thumbnails = try await imageURLs.concurrentMap(maxConcurrency: 4) { url in
    try await ImageLoader.loadThumbnail(from: url)
}
```

### Fire off side effects without collecting results

```swift
let recipientIDs = campaign.recipientIDs

try await recipientIDs.concurrentForEach(maxConcurrency: 10) { id in
    try await emailService.sendCampaign(campaign, to: id)
}
```

### Filter while transforming, concurrently

```swift
let productSKUs = warehouse.skus

// Only keep SKUs that are currently in stock.
let inStock = try await productSKUs.concurrentCompactMap { sku -> Product? in
    let product = try await inventory.lookup(sku)
    return product.quantity > 0 ? product : nil
}
```

### Race mirrored endpoints

```swift
// Hit two regions and use whichever responds first.
let config = try await ConcurrentRace.firstSuccess([
    { try await api.fetchConfig(host: .usEast) },
    { try await api.fetchConfig(host: .euWest) },
])
```

### Race a network fetch against a local cache warm-up

```swift
enum Source: Equatable { case network(Config), cache(Config) }

let winner = try await ConcurrentRace.firstSuccess([
    { Source.network(try await api.fetchConfig()) },
    {
        try await Task.sleep(nanoseconds: 50_000_000) // give the network a head start
        return Source.cache(try await localCache.loadConfig())
    },
])
```

### Handling partial failures in a race

```swift
// firstSuccess only fails if *every* candidate throws.
do {
    let result = try await ConcurrentRace.firstSuccess([
        { try await primaryCDN.fetch(asset) },
        { try await fallbackCDN.fetch(asset) },
    ])
    render(result)
} catch {
    showOfflinePlaceholder()
}
```
