import XCTest
@testable import SwiftUtilsNetworking

/// A `URLProtocol` stub that serves canned bytes (or an error) and counts how many
/// requests it actually handled, so tests can assert on de-duplication.
private final class MockDownloadURLProtocol: URLProtocol {
    static var responseData: Data = Data(repeating: 0x41, count: 4096)
    static var responseError: Error?
    static var statusCode: Int = 200
    static var requestDelayNanoseconds: UInt64 = 0
    private static var _requestCount = 0
    private static let lock = NSLock()

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requestCount
    }

    static func reset() {
        lock.lock()
        _requestCount = 0
        lock.unlock()
        responseData = Data(repeating: 0x41, count: 4096)
        responseError = nil
        statusCode = 200
        requestDelayNanoseconds = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        Self.lock.unlock()

        let delay = Self.requestDelayNanoseconds
        let work = { [weak self] in
            guard let self else { return }
            if let error = Self.responseError {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: Self.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(Self.responseData.count)"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Self.responseData)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(delay)), execute: work)
        } else {
            work()
        }
    }

    override func stopLoading() {}
}

final class DownloadManagerTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        MockDownloadURLProtocol.reset()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeManager(maxConcurrentDownloads: Int = 4) -> DownloadManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockDownloadURLProtocol.self]
        return DownloadManager(
            destinationDirectory: tempDirectory,
            maxConcurrentDownloads: maxConcurrentDownloads,
            session: URLSession(configuration: config)
        )
    }

    // MARK: - Basic downloads

    func testDownloadWritesFileToDestination() async throws {
        let manager = makeManager()
        let url = URL(string: "https://example.com/file.bin")!

        let fileURL = try await manager.download(url)

        XCTAssertEqual(fileURL.lastPathComponent, "file.bin")
        let data = try Data(contentsOf: fileURL)
        XCTAssertEqual(data, MockDownloadURLProtocol.responseData)
    }

    func testDownloadUsesCustomFilename() async throws {
        let manager = makeManager()
        let url = URL(string: "https://example.com/file.bin")!

        let fileURL = try await manager.download(url, filename: "renamed.dat")

        XCTAssertEqual(fileURL.lastPathComponent, "renamed.dat")
    }

    func testEventsStreamReportsCompletion() async throws {
        let manager = makeManager()
        let url = URL(string: "https://example.com/stream.bin")!

        var sawCompleted = false
        for try await event in await manager.events(for: url) {
            if case .completed = event { sawCompleted = true }
        }
        XCTAssertTrue(sawCompleted)
    }

    // MARK: - De-duplication

    func testConcurrentRequestsForSameURLShareOneTransfer() async throws {
        let manager = makeManager()
        MockDownloadURLProtocol.requestDelayNanoseconds = 50_000_000
        let url = URL(string: "https://example.com/shared.bin")!

        async let first = manager.download(url)
        async let second = manager.download(url)
        let (a, b) = try await (first, second)

        XCTAssertEqual(a, b)
        XCTAssertEqual(MockDownloadURLProtocol.requestCount, 1)
    }

    func testCompletedDownloadIsServedFromCacheWithoutRefetching() async throws {
        let manager = makeManager()
        let url = URL(string: "https://example.com/cached.bin")!

        _ = try await manager.download(url)
        _ = try await manager.download(url)

        XCTAssertEqual(MockDownloadURLProtocol.requestCount, 1)
    }

    func testForgetClearsCacheAndRemovesFile() async throws {
        let manager = makeManager()
        let url = URL(string: "https://example.com/forgettable.bin")!

        let fileURL = try await manager.download(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        await manager.forget(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        _ = try await manager.download(url)
        XCTAssertEqual(MockDownloadURLProtocol.requestCount, 2)
    }

    // MARK: - Errors

    func testServerErrorStatusCodeThrows() async {
        MockDownloadURLProtocol.statusCode = 404
        let manager = makeManager()
        let url = URL(string: "https://example.com/missing.bin")!

        do {
            _ = try await manager.download(url)
            XCTFail("Expected serverError to be thrown")
        } catch DownloadError.serverError(let statusCode) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkErrorPropagates() async {
        struct DummyError: Error {}
        MockDownloadURLProtocol.responseError = DummyError()
        let manager = makeManager()

        do {
            _ = try await manager.download(URL(string: "https://example.com/broken.bin")!)
            XCTFail("Expected network error to propagate")
        } catch {
            // expected — exact error type is wrapped by URLSession, just confirm it throws
        }
    }

    // MARK: - State

    func testIsDownloadingReflectsInFlightState() async throws {
        let manager = makeManager()
        MockDownloadURLProtocol.requestDelayNanoseconds = 80_000_000
        let url = URL(string: "https://example.com/inflight.bin")!

        let before = await manager.isDownloading(url)
        XCTAssertFalse(before)

        let task = Task { try await manager.download(url) }
        try await Task.sleep(nanoseconds: 10_000_000)

        let during = await manager.isDownloading(url)
        XCTAssertTrue(during)

        _ = try await task.value
        let after = await manager.isDownloading(url)
        XCTAssertFalse(after)
    }

    func testFractionCompletedComputesRatio() {
        let event = DownloadEvent.progress(bytesWritten: 50, totalBytes: 200)
        XCTAssertEqual(event.fractionCompleted, 0.25)

        let unknownTotal = DownloadEvent.progress(bytesWritten: 50, totalBytes: nil)
        XCTAssertNil(unknownTotal.fractionCompleted)

        let completed = DownloadEvent.completed(fileURL: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertNil(completed.fractionCompleted)
    }
}
