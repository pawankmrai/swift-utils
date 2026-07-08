import Foundation

// MARK: - Page

/// A single page of results returned by a pagination data source.
///
/// `Cursor` is generic so the same controller can drive page-number APIs
/// (`Cursor == Int`), opaque cursor/token APIs (`Cursor == String`), or any
/// other paging scheme the backend uses.
public struct Page<Item: Sendable, Cursor: Sendable>: Sendable {

    /// The items returned for this page.
    public let items: [Item]

    /// The cursor to request the next page, or `nil` if this is the last page.
    public let nextCursor: Cursor?

    public init(items: [Item], nextCursor: Cursor?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

// MARK: - PaginationController

/// An actor that drives incremental loading of paged API results.
///
/// `PaginationController` owns the accumulated item list, the current
/// cursor, and loading/error state, so view models don't have to hand-roll
/// "am I already loading" and "do I have more pages" bookkeeping for every
/// paged list screen. It works with any pagination scheme — page numbers,
/// opaque cursors, or `next` tokens — via a single async fetch closure.
///
/// Concurrent calls to `loadNextPage()` are automatically de-duplicated: if
/// a load is already in flight, later callers await the same in-flight
/// `Task` instead of firing a duplicate request.
///
/// ```swift
/// let controller = PaginationController<Post, Int> { page in
///     let response = try await api.fetchPosts(page: page ?? 1)
///     return Page(items: response.posts, nextCursor: response.hasMore ? (page ?? 1) + 1 : nil)
/// }
///
/// let firstBatch = try await controller.loadNextPage()
/// let allSoFar = await controller.items
/// ```
public actor PaginationController<Item: Sendable, Cursor: Sendable> {

    /// Fetches a single page of results for the given cursor.
    /// `nil` is passed for the very first page.
    public typealias FetchPage = @Sendable (Cursor?) async throws -> Page<Item, Cursor>

    /// All items accumulated so far, in page order.
    public private(set) var items: [Item] = []

    /// The cursor to use for the next fetch. `nil` after `reset()` or before
    /// the first successful load.
    public private(set) var nextCursor: Cursor?

    /// Whether an earlier page has been fetched and a `nextCursor` was
    /// returned, meaning more data is available.
    public private(set) var hasMore = true

    /// The most recent error raised by `fetch`, cleared on the next
    /// successful load.
    public private(set) var lastError: Error?

    private let fetch: FetchPage
    private var inFlightTask: Task<Page<Item, Cursor>, Error>?

    /// Creates a new pagination controller.
    /// - Parameter fetch: An async closure that loads one page for a given cursor.
    public init(fetch: @escaping FetchPage) {
        self.fetch = fetch
    }

    /// Whether a `loadNextPage()` call is currently in flight.
    public var isLoading: Bool {
        inFlightTask != nil
    }

    /// Loads the next page and appends its items to `items`.
    ///
    /// If a load is already in progress, this call awaits that same load
    /// rather than starting a second request. Returns an empty array
    /// without fetching if `hasMore` is already `false`.
    @discardableResult
    public func loadNextPage() async throws -> [Item] {
        guard hasMore else { return [] }

        if let inFlightTask {
            return try await inFlightTask.value.items
        }

        let cursor = nextCursor
        let fetchPage = fetch
        let task = Task { try await fetchPage(cursor) }
        inFlightTask = task

        do {
            let page = try await task.value
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            hasMore = page.nextCursor != nil
            lastError = nil
            inFlightTask = nil
            return page.items
        } catch {
            lastError = error
            inFlightTask = nil
            throw error
        }
    }

    /// Clears all accumulated state so the next `loadNextPage()` call
    /// starts a fresh sequence from the beginning.
    public func reset() {
        inFlightTask?.cancel()
        inFlightTask = nil
        items = []
        nextCursor = nil
        hasMore = true
        lastError = nil
    }

    /// Convenience for pull-to-refresh: resets state, then loads the first page.
    @discardableResult
    public func refresh() async throws -> [Item] {
        reset()
        return try await loadNextPage()
    }
}
