import XCTest
@testable import SwiftUtilsNetworking

/// A 1x1 transparent PNG — the smallest payload `UIImage(data:)` will decode successfully.
private let validPNGData = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
)!

/// A `URLProtocol` stub that serves canned data/errors and counts how many
/// requests it actually handled, so tests can assert on de-duplication.
private final class MockImageURLProtocol: URLProtocol {
    static var responseData: Data?
    static var responseError: Error?
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
        responseData = validPNGData
        responseError = nil
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
            let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = Self.responseData {
                self.client?.urlProtocol(self, didLoad: data)
            }
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

final class ImageLoaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockImageURLProtocol.reset()
    }

    private func makeLoader(diskCacheNamespace: String? = nil) -> ImageLoader {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockImageURLProtocol.self]
        return ImageLoader(
            diskCacheNamespace: diskCacheNamespace,
            session: URLSession(configuration: config)
        )
    }

    // MARK: - Basic loading

    func testLoadsImageFromNetwork() async throws {
        let loader = makeLoader()
        let image = try await loader.image(for: URL(string: "https://example.com/a.png")!)
        XCTAssertEqual(image.size.width, 1)
        XCTAssertEqual(MockImageURLProtocol.requestCount, 1)
    }

    func testInvalidImageDataThrows() async {
        MockImageURLProtocol.responseData = "not an image".data(using: .utf8)
        let loader = makeLoader()
        let url = URL(string: "https://example.com/bad.png")!

        do {
            _ = try await loader.image(for: url)
            XCTFail("Expected invalidImageData to be thrown")
        } catch ImageLoaderError.invalidImageData(let failedURL) {
            XCTAssertEqual(failedURL, url)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkErrorPropagates() async {
        struct DummyError: Error {}
        MockImageURLProtocol.responseError = DummyError()
        let loader = makeLoader()

        do {
            _ = try await loader.image(for: URL(string: "https://example.com/a.png")!)
            XCTFail("Expected network error to propagate")
        } catch {
            // expected — exact error type is wrapped by URLSession, just confirm it throws
        }
    }

    // MARK: - Caching

    func testSecondRequestIsServedFromMemoryCache() async throws {
        let loader = makeLoader()
        let url = URL(string: "https://example.com/a.png")!

        _ = try await loader.image(for: url)
        _ = try await loader.image(for: url)

        XCTAssertEqual(MockImageURLProtocol.requestCount, 1)
    }

    func testIsCachedInMemoryReflectsState() async throws {
        let loader = makeLoader()
        let url = URL(string: "https://example.com/a.png")!

        let before = await loader.isCachedInMemory(url)
        XCTAssertFalse(before)

        _ = try await loader.image(for: url)

        let after = await loader.isCachedInMemory(url)
        XCTAssertTrue(after)
    }

    func testClearMemoryCacheForcesRefetchWithoutDisk() async throws {
        let loader = makeLoader(diskCacheNamespace: nil)
        let url = URL(string: "https://example.com/a.png")!

        _ = try await loader.image(for: url)
        await loader.clearMemoryCache()
        _ = try await loader.image(for: url)

        XCTAssertEqual(MockImageURLProtocol.requestCount, 2)
    }

    func testDiskCacheServesFreshInstanceWithoutNetwork() async throws {
        let namespace = "image-loader-test-\(UUID().uuidString)"
        let url = URL(string: "https://example.com/a.png")!

        let writer = makeLoader(diskCacheNamespace: namespace)
        _ = try await writer.image(for: url)
        XCTAssertEqual(MockImageURLProtocol.requestCount, 1)

        // A brand-new loader instance has an empty memory cache, so this exercises the disk path.
        let reader = makeLoader(diskCacheNamespace: namespace)
        let image = try await reader.image(for: url)

        XCTAssertEqual(image.size.width, 1)
        XCTAssertEqual(MockImageURLProtocol.requestCount, 1, "Disk hit should not trigger a network request")

        await reader.clearAll()
    }

    // MARK: - De-duplication

    func testConcurrentRequestsForSameURLShareOneDownload() async throws {
        MockImageURLProtocol.requestDelayNanoseconds = 50_000_000 // 50ms
        let loader = makeLoader()
        let url = URL(string: "https://example.com/a.png")!

        async let first = loader.image(for: url)
        async let second = loader.image(for: url)
        async let third = loader.image(for: url)

        _ = try await (first, second, third)

        XCTAssertEqual(MockImageURLProtocol.requestCount, 1)
    }

    // MARK: - Cancellation

    func testCancelWithNoActiveTaskIsNoOp() async {
        let loader = makeLoader()
        await loader.cancel(URL(string: "https://example.com/nothing.png")!)
        // Should simply not crash or hang.
    }

    func testCancelStopsAwaitingCaller() async throws {
        MockImageURLProtocol.requestDelayNanoseconds = 200_000_000 // 200ms
        let loader = makeLoader()
        let url = URL(string: "https://example.com/a.png")!

        let task = Task { try await loader.image(for: url) }
        try await Task.sleep(nanoseconds: 20_000_000) // let the request start
        await loader.cancel(url)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to propagate")
        } catch {
            // expected — either CancellationError or a URLError caused by cancellation
        }
    }

    // MARK: - Prefetch

    func testPrefetchEventuallyPopulatesMemoryCache() async throws {
        let loader = makeLoader()
        let url = URL(string: "https://example.com/a.png")!

        await loader.prefetch([url])

        var cached = false
        for _ in 0..<20 {
            cached = await loader.isCachedInMemory(url)
            if cached { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(cached)
        XCTAssertEqual(MockImageURLProtocol.requestCount, 1)
    }
}
