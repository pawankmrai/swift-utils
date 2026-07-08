import XCTest
@testable import SwiftUtilsNetworking

private struct Item: Sendable, Equatable {
    let id: Int
}

private actor CallCounter {
    private(set) var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

final class PaginationControllerTests: XCTestCase {

    private func makeController(
        pageSize: Int = 2,
        totalPages: Int = 3
    ) -> PaginationController<Item, Int> {
        PaginationController<Item, Int> { cursor in
            let page = cursor ?? 1
            let start = (page - 1) * pageSize
            let items = (start..<(start + pageSize)).map { Item(id: $0) }
            let hasMore = page < totalPages
            return Page(items: items, nextCursor: hasMore ? page + 1 : nil)
        }
    }

    // MARK: - Basic loading

    func testLoadsFirstPage() async throws {
        let controller = makeController()
        let firstPage = try await controller.loadNextPage()

        XCTAssertEqual(firstPage, [Item(id: 0), Item(id: 1)])
        let items = await controller.items
        XCTAssertEqual(items, firstPage)
        let hasMore = await controller.hasMore
        XCTAssertTrue(hasMore)
    }

    func testAccumulatesItemsAcrossPages() async throws {
        let controller = makeController()

        _ = try await controller.loadNextPage()
        _ = try await controller.loadNextPage()
        _ = try await controller.loadNextPage()

        let items = await controller.items
        XCTAssertEqual(items.map(\.id), Array(0..<6))
        let hasMore = await controller.hasMore
        XCTAssertFalse(hasMore)
    }

    func testStopsFetchingAfterLastPage() async throws {
        let controller = makeController(pageSize: 2, totalPages: 1)

        let firstPage = try await controller.loadNextPage()
        XCTAssertEqual(firstPage.count, 2)

        let hasMore = await controller.hasMore
        XCTAssertFalse(hasMore)

        // Calling again should not fetch and should return no new items.
        let extra = try await controller.loadNextPage()
        XCTAssertEqual(extra, [])
    }

    // MARK: - Reset & refresh

    func testResetClearsState() async throws {
        let controller = makeController()
        _ = try await controller.loadNextPage()

        await controller.reset()

        let items = await controller.items
        XCTAssertTrue(items.isEmpty)
        let hasMore = await controller.hasMore
        XCTAssertTrue(hasMore)
        let nextCursor = await controller.nextCursor
        XCTAssertNil(nextCursor)
    }

    func testRefreshReloadsFromStart() async throws {
        let controller = makeController()
        _ = try await controller.loadNextPage()
        _ = try await controller.loadNextPage()

        let refreshed = try await controller.refresh()

        XCTAssertEqual(refreshed, [Item(id: 0), Item(id: 1)])
        let items = await controller.items
        XCTAssertEqual(items, refreshed)
    }

    // MARK: - Error handling

    func testErrorIsSurfacedAndRecorded() async throws {
        struct TestError: Error, Equatable {}

        let controller = PaginationController<Item, Int> { _ in
            throw TestError()
        }

        do {
            _ = try await controller.loadNextPage()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is TestError)
        }

        let lastError = await controller.lastError
        XCTAssertNotNil(lastError)
        // A failed fetch should not advance cursor or mark hasMore false.
        let hasMore = await controller.hasMore
        XCTAssertTrue(hasMore)
    }

    // MARK: - Concurrent de-duplication

    func testConcurrentLoadsAreDeduplicated() async throws {
        let counter = CallCounter()
        let controller = PaginationController<Item, Int> { cursor in
            _ = await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            let page = cursor ?? 1
            return Page(items: [Item(id: page)], nextCursor: page < 2 ? page + 1 : nil)
        }

        async let first = controller.loadNextPage()
        async let second = controller.loadNextPage()

        let (firstResult, secondResult) = try await (first, second)

        // Both calls should observe the same first page since the second
        // call joins the in-flight request rather than starting a new one.
        XCTAssertEqual(firstResult, secondResult)
        let callCount = await counter.count
        XCTAssertEqual(callCount, 1)
    }

    func testIsLoadingReflectsInFlightState() async throws {
        let controller = PaginationController<Item, Int> { cursor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            return Page(items: [Item(id: 0)], nextCursor: nil)
        }

        let isLoadingBefore = await controller.isLoading
        XCTAssertFalse(isLoadingBefore)

        async let load: [Item] = controller.loadNextPage()
        try await Task.sleep(nanoseconds: 5_000_000)

        let isLoadingDuring = await controller.isLoading
        XCTAssertTrue(isLoadingDuring)

        _ = try await load
        let isLoadingAfter = await controller.isLoading
        XCTAssertFalse(isLoadingAfter)
    }
}
