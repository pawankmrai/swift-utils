import Foundation

/// Errors thrown by ``CodableStore``.
public enum CodableStoreError: LocalizedError {
    /// An element with the given identifier was not found.
    case notFound(String)
    /// Encoding the collection to JSON failed.
    case encodingFailed(Error)
    /// Decoding the collection from JSON failed.
    case decodingFailed(Error)
    /// The underlying file system operation failed.
    case underlyingError(Error)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):       return "No element found with id: \(id)"
        case .encodingFailed(let e):  return "Encoding failed: \(e.localizedDescription)"
        case .decodingFailed(let e):  return "Decoding failed: \(e.localizedDescription)"
        case .underlyingError(let e): return e.localizedDescription
        }
    }
}

/// A lightweight, thread-safe, disk-backed collection store for a single
/// `Codable & Identifiable` model type — think of it as a tiny local database
/// for small datasets (settings lists, drafts, bookmarks, cached records).
///
/// Every mutating call persists the whole collection to a single JSON file
/// using an atomic write, so the on-disk data is never left half-written.
/// Reads are served from an in-memory snapshot, so they are fast and never
/// touch the disk after the initial load.
///
/// All access is serialized through an internal concurrent queue using a
/// barrier for writes, making the store safe to share across threads.
///
/// ## Quick start
/// ```swift
/// struct Note: Codable, Identifiable { let id: UUID; var text: String }
///
/// let store = try CodableStore<Note>(filename: "notes.json")
/// try store.upsert(Note(id: UUID(), text: "Buy milk"))
/// let all = store.all()
/// ```
///
/// - Note: Designed for modest collections (hundreds to low thousands of
///   items). For large datasets or relational queries, prefer Core Data.
public final class CodableStore<Element: Codable & Identifiable> where Element.ID: Hashable {

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.swiftutils.codablestore", attributes: .concurrent)

    /// In-memory snapshot, keyed by element id to keep lookups O(1).
    /// Insertion order is preserved separately so ``all()`` is stable.
    private var index: [Element.ID: Element] = [:]
    private var order: [Element.ID] = []

    /// Creates a store backed by `filename` inside `directory`
    /// (defaults to the app's Application Support directory).
    ///
    /// If the file already exists its contents are loaded immediately;
    /// otherwise the store starts empty.
    ///
    /// - Parameters:
    ///   - filename: The JSON file name, e.g. `"notes.json"`.
    ///   - directory: The container directory. Defaults to Application Support.
    ///   - encoder: JSON encoder; defaults to ISO 8601 dates and pretty printing.
    ///   - decoder: JSON decoder; defaults to ISO 8601 dates.
    public init(
        filename: String,
        directory: URL? = nil,
        encoder: JSONEncoder = CodableStore.defaultEncoder,
        decoder: JSONDecoder = CodableStore.defaultDecoder
    ) throws {
        let baseDir: URL
        if let directory {
            baseDir = directory
        } else {
            baseDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.fileURL = baseDir.appendingPathComponent(filename)
        self.encoder = encoder
        self.decoder = decoder
        try load()
    }

    // MARK: - Reads

    /// All elements, in insertion order.
    public func all() -> [Element] {
        queue.sync { order.compactMap { index[$0] } }
    }

    /// The number of stored elements.
    public var count: Int {
        queue.sync { order.count }
    }

    /// The element with the given id, or `nil` if absent.
    public func element(withID id: Element.ID) -> Element? {
        queue.sync { index[id] }
    }

    /// Whether an element with the given id exists.
    public func contains(id: Element.ID) -> Bool {
        queue.sync { index[id] != nil }
    }

    /// All elements matching `predicate`, in insertion order.
    public func filter(_ predicate: (Element) -> Bool) -> [Element] {
        queue.sync { order.compactMap { index[$0] }.filter(predicate) }
    }

    // MARK: - Writes

    /// Inserts a new element or updates the existing one with the same id,
    /// then persists the collection. Updates keep the element's original
    /// position; inserts are appended.
    public func upsert(_ element: Element) throws {
        try queue.sync(flags: .barrier) {
            if index[element.id] == nil {
                order.append(element.id)
            }
            index[element.id] = element
            try persist()
        }
    }

    /// Inserts or updates many elements in a single atomic write.
    public func upsert(_ elements: [Element]) throws {
        try queue.sync(flags: .barrier) {
            for element in elements {
                if index[element.id] == nil { order.append(element.id) }
                index[element.id] = element
            }
            try persist()
        }
    }

    /// Removes the element with the given id. Throws ``CodableStoreError/notFound(_:)``
    /// if no such element exists.
    public func delete(id: Element.ID) throws {
        try queue.sync(flags: .barrier) {
            guard index[id] != nil else {
                throw CodableStoreError.notFound("\(id)")
            }
            index[id] = nil
            order.removeAll { $0 == id }
            try persist()
        }
    }

    /// Removes every element matching `predicate`. Returns the number removed.
    @discardableResult
    public func deleteAll(where predicate: (Element) -> Bool) throws -> Int {
        try queue.sync(flags: .barrier) {
            let toRemove = order.compactMap { index[$0] }.filter(predicate).map(\.id)
            for id in toRemove { index[id] = nil }
            order.removeAll { toRemove.contains($0) }
            if !toRemove.isEmpty { try persist() }
            return toRemove.count
        }
    }

    /// Removes all elements and persists the empty collection.
    public func removeAll() throws {
        try queue.sync(flags: .barrier) {
            index.removeAll()
            order.removeAll()
            try persist()
        }
    }

    // MARK: - Persistence

    /// Loads the collection from disk into memory. Called automatically on init.
    private func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return }
            let elements = try decoder.decode([Element].self, from: data)
            index = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
            order = elements.map(\.id)
        } catch let error as DecodingError {
            throw CodableStoreError.decodingFailed(error)
        } catch {
            throw CodableStoreError.underlyingError(error)
        }
    }

    /// Encodes the current snapshot and writes it atomically. Caller must hold
    /// the write barrier.
    private func persist() throws {
        let elements = order.compactMap { index[$0] }
        let data: Data
        do {
            data = try encoder.encode(elements)
        } catch {
            throw CodableStoreError.encodingFailed(error)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw CodableStoreError.underlyingError(error)
        }
    }

    /// Default encoder: ISO 8601 dates, pretty printed for human-readable files.
    public static var defaultEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Default decoder: ISO 8601 dates.
    public static var defaultDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
