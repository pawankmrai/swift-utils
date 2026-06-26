# ImageLoader

An actor-based remote image loader with in-memory and on-disk caching, automatic request de-duplication, cancellation, and a cell-reuse-safe `UIImageView` convenience.

## API

| Type / Member | Description |
|---|---|
| `ImageLoader` | Actor. Loads, decodes, and caches images fetched over HTTP. |
| `ImageLoader.shared` | A shared, app-wide instance using `URLSession.shared` and the `"ImageLoader"` disk namespace. |
| `ImageLoader.init(memoryCountLimit:diskCacheNamespace:session:)` | Creates a loader with a custom memory cache size, disk namespace (or `nil` to disable disk caching), and `URLSession`. |
| `ImageLoader.image(for:)` | `async throws -> UIImage`. Checks memory, then disk, then network. Concurrent calls for the same URL share one download. |
| `ImageLoader.prefetch(_:)` | Starts loading a list of URLs in the background without waiting for results. |
| `ImageLoader.cancel(_:)` | Cancels the in-flight download for a URL, if any. |
| `ImageLoader.isCachedInMemory(_:)` | Returns whether a URL's image is currently in the memory cache. |
| `ImageLoader.clearMemoryCache()` | Empties the in-memory cache only. |
| `ImageLoader.clearAll()` | Empties both the in-memory and on-disk caches. |
| `ImageLoaderError.invalidImageData(URL)` | Thrown when the bytes returned for a URL can't be decoded as an image. |
| `UIImageView.setImage(from:placeholder:loader:animated:)` | Loads an image via an `ImageLoader` and sets it, guarding against stale results on reused views. |

## Examples

### Basic loading

```swift
import SwiftUtilsNetworking

let image = try await ImageLoader.shared.image(for: url)
imageView.image = image
```

### UIKit, cell-reuse safe

The bundled `UIImageView` extension is the easiest way to use `ImageLoader` in a table or collection view — it automatically discards results that arrive after the cell has been reused for a different URL.

```swift
override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! ThumbnailCell
    let item = items[indexPath.row]

    cell.thumbnailView.setImage(
        from: item.imageURL,
        placeholder: UIImage(named: "placeholder")
    )
    return cell
}
```

### Prefetching ahead of a scroll

```swift
func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
    let urls = indexPaths.map { items[$0.row].imageURL }
    Task { await ImageLoader.shared.prefetch(urls) }
}
```

### A dedicated loader with custom limits

Use a separate instance — rather than `.shared` — when you want different cache limits or an isolated disk namespace, e.g. for a feature that loads many large images.

```swift
let galleryLoader = ImageLoader(memoryCountLimit: 50, diskCacheNamespace: "gallery-images")

let image = try await galleryLoader.image(for: photo.fullSizeURL)
```

### Memory-only loader (no disk persistence)

```swift
let scratchLoader = ImageLoader(diskCacheNamespace: nil)
```

### Handling decode failures

```swift
do {
    let image = try await ImageLoader.shared.image(for: url)
    imageView.image = image
} catch ImageLoaderError.invalidImageData(let badURL) {
    print("Server returned non-image data for \(badURL)")
} catch {
    print("Failed to load image: \(error)")
}
```

### Cancelling a download

```swift
// e.g. the user scrolled away or backed out of a screen before the image arrived
await ImageLoader.shared.cancel(url)
```

### Clearing caches

```swift
// Free memory on a low-memory warning
await ImageLoader.shared.clearMemoryCache()

// Wipe everything, e.g. on logout or in a "Clear cache" settings action
await ImageLoader.shared.clearAll()
```

### Checking cache state before showing a spinner

```swift
if await ImageLoader.shared.isCachedInMemory(url) {
    imageView.image = try? await ImageLoader.shared.image(for: url)
} else {
    spinner.startAnimating()
    Task {
        defer { spinner.stopAnimating() }
        imageView.image = try? await ImageLoader.shared.image(for: url)
    }
}
```
