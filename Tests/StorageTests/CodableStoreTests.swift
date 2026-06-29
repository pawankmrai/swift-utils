import XCTest
@testable import SwiftUtilsStorage

final class CodableStoreTests: XCTestCase {

    struct Note: Codable, Identifiable, Equatable {
        let id: Int
        var text: String
    }

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() throws -> CodableStore<Note> {
        try CodableStore<Note>(filename: "notes.json", directory: tempDir)
    }

    // MARK: - Insert & Read

    func testUpsertAndAll() throws {
        let store = try makeStore()
        try store.upsert(Note(id: 1, text: "first"))
        try store.upsert(Note(id: 2, text: "second"))
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.all().map(\.id), [1, 2]) // insertion order preserved
    }

    func testElementByID() throws {
        let store = try makeStore()
        try store.upsert(Note(id: 7, text: "lucky"))
        XCTAssertEqual(store.element(withID: 7)?.text, "lucky")
        XCTAssertNil(store.element(withID: 99))
    }

    func testContains() throws {
        let store = try makeStore()
        try store.upsert(Note(id: 3, text: "x"))
        XCTAssertTrue(store.contains(id: 3))
        XCTAssertFalse(store.contains(id: 4))
    }

    // MARK: - Update

    func testUpsertUpdatesInPlace() throws {
        let store = try makeStore()
        try store.upsert(Note(id: 1, text: "a"))
        try store.upsert(Note(id: 2, text: "b"))
        try store.upsert(Note(id: 1, text: "a-updated"))
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.element(withID: 1)?.text, "a-updated")
        XCTAssertEqual(store.all().map(\.id), [1, 2]) // position unchanged on update
    }

    func testBatchUpsert() throws {
        let store = try makeStore()
        try store.upsert([Note(id: 1, text: "a"), Note(id: 2, text: "b"), Note(id: 3, text: "c")])
        XCTAssertEqual(store.count, 3)
    }

    // MARK: - Delete

    func testDeleteByID() throws {
        let store = try makeStore()
        try store.upsert(Note(id: 1, text: "a"))
        try store.upsert(Note(id: 2, text: "b"))
        try store.delete(id: 1)
        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.contains(id: 1))
    }

    func testDeleteMissingThrows() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.delete(id: 42)) { error in
            guard case CodableStoreError.notFound = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    func testDeleteAllWherePredicate() throws {
        let store = try makeStore()
        try store.upsert([
            Note(id: 1, text: "keep"),
            Note(id: 2, text: "drop"),
            Note(id: 3, text: "drop"),
        ])
        let removed = try store.deleteAll { $0.text == "drop" }
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(store.all().map(\.id), [1])
    }

    func testRemoveAll() throws {
        let store = try makeStore()
        try store.upsert([Note(id: 1, text: "a"), Note(id: 2, text: "b")])
        try store.removeAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - Filter

    func testFilter() throws {
        let store = try makeStore()
        try store.upsert([
            Note(id: 1, text: "apple"),
            Note(id: 2, text: "banana"),
            Note(id: 3, text: "apricot"),
        ])
        let aFruits = store.filter { $0.text.hasPrefix("a") }
        XCTAssertEqual(aFruits.map(\.id), [1, 3])
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() throws {
        let store1 = try makeStore()
        try store1.upsert(Note(id: 1, text: "persisted"))

        // A new store pointed at the same file should load existing data.
        let store2 = try makeStore()
        XCTAssertEqual(store2.count, 1)
        XCTAssertEqual(store2.element(withID: 1)?.text, "persisted")
    }

    func testEmptyFileLoadsEmpty() throws {
        let store = try makeStore()
        XCTAssertEqual(store.count, 0)
    }

    func testFileWrittenToDisk() throws {
        let store = try makeStore()
        try store.upsert(Note(id: 1, text: "x"))
        let fileURL = tempDir.appendingPathComponent("notes.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Concurrency

    func testConcurrentUpsertsAreThreadSafe() throws {
        let store = try makeStore()
        let group = DispatchGroup()
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                try? store.upsert(Note(id: i, text: "n\(i)"))
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(store.count, 100)
    }
}
