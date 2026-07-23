import Foundation

// MARK: - DownloadError

/// Errors thrown by `DownloadManager`.
public enum DownloadError: Error, Equatable, Sendable {
    /// The server response wasn't an `HTTPURLResponse`.
    case invalidResponse
    /// The server responded with a non-2xx status code.
    case serverError(statusCode: Int)
    /// The download was cancelled before it produced a file.
    case cancelled
}

// MARK: - DownloadEvent

/// A single update emitted while a download is in progress.
public enum DownloadEvent: Sendable {
    /// Bytes have been written to disk. `totalBytes` is `nil` when the server
    /// didn't send a `Content-Length` header.
    case progress(bytesWritten: Int64, totalBytes: Int64?)
    /// The download finished and the file is available at `fileURL`.
    case completed(fileURL: URL)

    /// A `0...1` completion fraction, or `nil` if the total size is unknown or this is a `.completed` event.
    public var fractionCompleted: Double? {
        guard case let .progress(written, total) = self, let total, total > 0 else { return nil }
        return min(1, Double(written) / Double(total))
    }
}

// MARK: - DownloadManager

/// An actor-based file downloader with request de-duplication, a bounded number
/// of concurrent transfers, and observable progress.
///
/// Downloading the same URL twice while the first download is still running
/// joins the existing transfer instead of starting a second one — every caller
/// observes the same progress and receives the same completed file. Once a URL
/// has finished downloading, later calls return the cached file immediately
/// (as long as it still exists on disk) without hitting the network again.
///
/// ```swift
/// for try await event in DownloadManager.shared.events(for: url) {
///     switch event {
///     case .progress(let written, let total):
///         updateProgressBar(written: written, total: total)
///     case .completed(let fileURL):
///         play(fileURL)
///     }
/// }
/// ```
public actor DownloadManager {

    private enum State {
        case inProgress(written: Int64, total: Int64?)
        case completed(URL)
        case failed(Error)
    }

    /// A shared, app-wide download manager instance.
    public static let shared = DownloadManager()

    private let session: URLSession
    private let destinationDirectory: URL
    private let maxConcurrentDownloads: Int

    private var runningTasks: [URL: Task<URL, Error>] = [:]
    private var states: [URL: State] = [:]

    private var availableSlots: Int
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a new download manager.
    /// - Parameters:
    ///   - destinationDirectory: Where finished downloads are saved. Defaults to a `"Downloads"` subdirectory of the app's Caches directory.
    ///   - maxConcurrentDownloads: The maximum number of transfers that run at once; additional downloads queue until a slot frees up.
    ///   - session: The `URLSession` used to fetch data. Defaults to `.shared`.
    public init(
        destinationDirectory: URL? = nil,
        maxConcurrentDownloads: Int = 4,
        session: URLSession = .shared
    ) {
        self.session = session
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.availableSlots = max(1, maxConcurrentDownloads)
        if let destinationDirectory {
            self.destinationDirectory = destinationDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.destinationDirectory = caches.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    /// Starts (or attaches to) a download for `url`, streaming progress and the final file URL.
    ///
    /// If `url` already has an in-flight download, this attaches to it rather than starting a
    /// duplicate transfer. If `url` was already downloaded and the file still exists on disk,
    /// the stream immediately yields a single `.completed` event.
    /// - Parameters:
    ///   - url: The remote file to download.
    ///   - filename: The name to save the file under. Defaults to `url.lastPathComponent`.
    public func events(for url: URL, filename: String? = nil) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let pollTask = Task {
                await self.ensureStarted(url, filename: filename)
                while !Task.isCancelled {
                    switch await self.currentState(for: url) {
                    case .inProgress(let written, let total):
                        continuation.yield(.progress(bytesWritten: written, totalBytes: total))
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    case .completed(let fileURL):
                        continuation.yield(.completed(fileURL: fileURL))
                        continuation.finish()
                        return
                    case .failed(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in pollTask.cancel() }
        }
    }

    /// Downloads `url` and returns the local file URL once complete, discarding intermediate progress.
    @discardableResult
    public func download(_ url: URL, filename: String? = nil) async throws -> URL {
        for try await event in events(for: url, filename: filename) {
            if case let .completed(fileURL) = event { return fileURL }
        }
        throw DownloadError.cancelled
    }

    /// Cancels the in-flight download for `url`, if any. Subscribers receive `DownloadError.cancelled`.
    public func cancel(_ url: URL) {
        runningTasks[url]?.cancel()
    }

    /// Cancels every in-flight download.
    public func cancelAll() {
        for task in runningTasks.values { task.cancel() }
    }

    /// Whether `url` currently has an active, in-flight download.
    public func isDownloading(_ url: URL) -> Bool {
        runningTasks[url] != nil
    }

    /// Removes a previously downloaded file (if any) and clears its cached state, so the next
    /// call to `events(for:)`/`download(_:)` re-fetches it from the network.
    public func forget(_ url: URL) {
        if case let .completed(fileURL)? = states[url] {
            try? FileManager.default.removeItem(at: fileURL)
        }
        states[url] = nil
    }

    // MARK: - Private

    private func ensureStarted(_ url: URL, filename: String?) {
        if runningTasks[url] != nil { return }
        if case let .completed(fileURL)? = states[url], FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }

        states[url] = .inProgress(written: 0, total: nil)
        let transfer = Task<URL, Error> { try await self.runDownload(url: url, filename: filename) }
        runningTasks[url] = transfer

        Task {
            do {
                let fileURL = try await transfer.value
                await self.markCompleted(url, fileURL: fileURL)
            } catch {
                await self.markFailed(url, error: error)
            }
        }
    }

    private func runDownload(url: URL, filename: String?) async throws -> URL {
        await acquireSlot()
        do {
            let result = try await transferData(url: url, filename: filename)
            releaseSlot()
            return result
        } catch {
            releaseSlot()
            throw error
        }
    }

    private func transferData(url: URL, filename: String?) async throws -> URL {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw DownloadError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }
        let total: Int64? = http.expectedContentLength >= 0 ? http.expectedContentLength : nil

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let tempURL = destinationDirectory.appendingPathComponent(UUID().uuidString + ".part")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)

        var written: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(65_536)

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 65_536 {
                    handle.write(buffer)
                    written += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    updateProgress(url, written: written, total: total)
                }
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }

        if !buffer.isEmpty {
            handle.write(buffer)
            written += Int64(buffer.count)
        }
        try? handle.close()
        updateProgress(url, written: written, total: total)

        let finalName = filename ?? (url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent)
        let destination = destinationDirectory.appendingPathComponent(finalName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func updateProgress(_ url: URL, written: Int64, total: Int64?) {
        states[url] = .inProgress(written: written, total: total)
    }

    private func markCompleted(_ url: URL, fileURL: URL) {
        states[url] = .completed(fileURL)
        runningTasks[url] = nil
    }

    private func markFailed(_ url: URL, error: Error) {
        states[url] = .failed(error)
        runningTasks[url] = nil
    }

    private func currentState(for url: URL) -> State {
        states[url] ?? .inProgress(written: 0, total: nil)
    }

    private func acquireSlot() async {
        if availableSlots > 0 {
            availableSlots -= 1
            return
        }
        await withCheckedContinuation { continuation in
            slotWaiters.append(continuation)
        }
    }

    private func releaseSlot() {
        if slotWaiters.isEmpty {
            availableSlots += 1
        } else {
            slotWaiters.removeFirst().resume()
        }
    }
}
