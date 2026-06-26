import UIKit

// MARK: - ImageLoaderError

/// Errors thrown by `ImageLoader`.
public enum ImageLoaderError: Error, Equatable {
    /// The data returned for `url` could not be decoded into an image.
    case invalidImageData(URL)
}

// MARK: - ImageLoader

/// An actor-based image loader with in-memory and on-disk caching, request
/// de-duplication, and cancellation support.
///
/// `ImageLoader` is a lightweight, dependency-free alternative to rolling your
/// own `URLSession` + `NSCache` pipeline for remote images. Repeated requests
/// for the same URL are served from memory or disk, and concurrent requests
/// for a URL that hasn't finished downloading yet share a single underlying
/// network call instead of each starting their own.
///
/// ```swift
/// let image = try await ImageLoader.shared.image(for: url)
/// imageView.image = image
/// ```
///
/// For UIKit, the bundled `UIImageView` convenience handles cancellation-safe
/// loading (including cell reuse) automatically — see `setImage(from:)`.
public actor ImageLoader {

    /// A shared, app-wide image loader instance.
    public static let shared = ImageLoader()

    private let memoryCache: NSCache<NSString, UIImage>
    private let diskURL: URL?
    private let session: URLSession
    private var activeTasks: [URL: Task<UIImage, Error>] = [:]

    /// Creates a new image loader.
    /// - Parameters:
    ///   - memoryCountLimit: Maximum number of images to keep in the in-memory cache. `0` means no limit, matching `NSCache` defaults.
    ///   - diskCacheNamespace: Subdirectory name under the app's Caches directory used for on-disk persistence. Pass `nil` to disable disk caching.
    ///   - session: The `URLSession` used to fetch images. Defaults to `.shared`.
    public init(
        memoryCountLimit: Int = 200,
        diskCacheNamespace: String? = "ImageLoader",
        session: URLSession = .shared
    ) {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = memoryCountLimit
        self.memoryCache = cache
        self.session = session

        if let diskCacheNamespace,
           let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            self.diskURL = caches.appendingPathComponent(diskCacheNamespace, isDirectory: true)
        } else {
            self.diskURL = nil
        }
    }

    /// Loads the image at `url`, checking memory, then disk, then the network, in that order.
    ///
    /// Concurrent calls for the same `url` share a single in-flight download — only one
    /// network request is made no matter how many callers ask for it at once.
    public func image(for url: URL) async throws -> UIImage {
        let key = url.absoluteString as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        if let diskImage = loadFromDisk(url) {
            memoryCache.setObject(diskImage, forKey: key)
            return diskImage
        }
        if let existingTask = activeTasks[url] {
            return try await existingTask.value
        }

        let session = self.session
        let task = Task<UIImage, Error> {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else {
                throw ImageLoaderError.invalidImageData(url)
            }
            return image
        }
        activeTasks[url] = task

        do {
            let image = try await task.value
            activeTasks[url] = nil
            memoryCache.setObject(image, forKey: key)
            saveToDisk(image, for: url)
            return image
        } catch {
            activeTasks[url] = nil
            throw error
        }
    }

    /// Begins loading each URL in the background without waiting for the result.
    /// Useful for warming the cache ahead of a scroll, e.g. from `UITableViewDataSourcePrefetching`.
    public func prefetch(_ urls: [URL]) {
        for url in urls where activeTasks[url] == nil {
            Task { try? await image(for: url) }
        }
    }

    /// Cancels the in-flight download for `url`, if any. Callers already awaiting
    /// that download will receive a cancellation error.
    public func cancel(_ url: URL) {
        activeTasks[url]?.cancel()
        activeTasks[url] = nil
    }

    /// Whether `url`'s image is currently held in the in-memory cache.
    public func isCachedInMemory(_ url: URL) -> Bool {
        memoryCache.object(forKey: url.absoluteString as NSString) != nil
    }

    /// Removes everything from the in-memory cache. The on-disk cache is left untouched.
    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// Removes everything from both the in-memory and on-disk caches.
    public func clearAll() {
        memoryCache.removeAllObjects()
        if let diskURL {
            try? FileManager.default.removeItem(at: diskURL)
        }
    }

    // MARK: Disk I/O

    private func diskFileURL(for url: URL) -> URL? {
        guard let diskURL else { return nil }
        let safeName = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            ?? UUID().uuidString
        return diskURL.appendingPathComponent(safeName)
    }

    private func loadFromDisk(_ url: URL) -> UIImage? {
        guard let fileURL = diskFileURL(for: url),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(_ image: UIImage, for url: URL) {
        guard let fileURL = diskFileURL(for: url),
              let data = image.pngData() else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Disk persistence is best-effort; the in-memory cache remains authoritative.
        }
    }
}

// MARK: - UIImageView Convenience

private enum AssociatedKeys {
    static var inFlightImageURL: UInt8 = 0
}

public extension UIImageView {

    /// The URL most recently requested via `setImage(from:)`, used to guard against
    /// stale results landing on a reused view (e.g. a recycled table/collection view cell).
    private var inFlightImageURL: URL? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.inFlightImageURL) as? URL }
        set { objc_setAssociatedObject(self, &AssociatedKeys.inFlightImageURL, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    /// Loads and sets the image at `url` via `ImageLoader`, with an optional placeholder shown
    /// immediately and an optional cross-fade once the real image arrives.
    ///
    /// Safe to call from `UITableView`/`UICollectionView` `cellForRow`/`cellForItem`: if the same
    /// view is reused for a different URL before this one finishes loading, the stale result is
    /// discarded instead of overwriting the newer request.
    func setImage(
        from url: URL,
        placeholder: UIImage? = nil,
        loader: ImageLoader = .shared,
        animated: Bool = true
    ) {
        inFlightImageURL = url
        image = placeholder
        Task { [weak self] in
            guard let loadedImage = try? await loader.image(for: url) else { return }
            guard let self, self.inFlightImageURL == url else { return }
            if animated {
                UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                    self.image = loadedImage
                }
            } else {
                self.image = loadedImage
            }
        }
    }
}
