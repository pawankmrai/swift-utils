import XCTest
import CoreData
@testable import SwiftUtilsStorage

@objc(TestNote)
final class TestNote: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var createdAt: Date
}

final class CoreDataStackTests: XCTestCase {

    private func makeModel() -> NSManagedObjectModel {
        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false

        let titleAttr = NSAttributeDescription()
        titleAttr.name = "title"
        titleAttr.attributeType = .stringAttributeType
        titleAttr.isOptional = false

        let dateAttr = NSAttributeDescription()
        dateAttr.name = "createdAt"
        dateAttr.attributeType = .dateAttributeType
        dateAttr.isOptional = false

        let entity = NSEntityDescription()
        entity.name = "TestNote"
        entity.managedObjectClassName = NSStringFromClass(TestNote.self)
        entity.properties = [idAttr, titleAttr, dateAttr]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private func makeStack(
        storeType: CoreDataStack.StoreType = .inMemory,
        storeURL: URL? = nil
    ) throws -> CoreDataStack {
        try CoreDataStack(modelName: "TestModel", model: makeModel(), storeType: storeType, storeURL: storeURL)
    }

    // MARK: - Create & fetch

    func testCreateAndFetch() throws {
        let stack = try makeStack()
        let note = stack.create(TestNote.self, in: stack.viewContext)
        note.id = UUID()
        note.title = "Hello"
        note.createdAt = Date()
        try stack.save(stack.viewContext)

        let results = try stack.fetch(TestNote.self, in: stack.viewContext)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Hello")
    }

    func testFetchWithPredicateAndSort() throws {
        let stack = try makeStack()
        for i in 0..<5 {
            let note = stack.create(TestNote.self, in: stack.viewContext)
            note.id = UUID()
            note.title = "Note \(i)"
            note.createdAt = Date().addingTimeInterval(Double(i))
        }
        try stack.save(stack.viewContext)

        let predicate = NSPredicate(format: "title != %@", "Note 0")
        let sort = [NSSortDescriptor(key: "title", ascending: false)]
        let results = try stack.fetch(TestNote.self, predicate: predicate, sortDescriptors: sort, in: stack.viewContext)
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.first?.title, "Note 4")
    }

    func testFetchRespectsLimit() throws {
        let stack = try makeStack()
        for i in 0..<10 {
            let note = stack.create(TestNote.self, in: stack.viewContext)
            note.id = UUID()
            note.title = "Item \(i)"
            note.createdAt = Date()
        }
        try stack.save(stack.viewContext)

        let results = try stack.fetch(TestNote.self, limit: 3, in: stack.viewContext)
        XCTAssertEqual(results.count, 3)
    }

    // MARK: - Count

    func testCount() throws {
        let stack = try makeStack()
        for i in 0..<3 {
            let note = stack.create(TestNote.self, in: stack.viewContext)
            note.id = UUID()
            note.title = "Item \(i)"
            note.createdAt = Date()
        }
        try stack.save(stack.viewContext)

        XCTAssertEqual(try stack.count(TestNote.self, in: stack.viewContext), 3)
    }

    // MARK: - Delete

    func testDeleteSingleObject() throws {
        let stack = try makeStack()
        let note = stack.create(TestNote.self, in: stack.viewContext)
        note.id = UUID()
        note.title = "ToDelete"
        note.createdAt = Date()
        try stack.save(stack.viewContext)

        try stack.delete(note, in: stack.viewContext)

        let results = try stack.fetch(TestNote.self, in: stack.viewContext)
        XCTAssertTrue(results.isEmpty)
    }

    func testBatchDeleteInMemoryFallback() throws {
        let stack = try makeStack(storeType: .inMemory)
        for i in 0..<4 {
            let note = stack.create(TestNote.self, in: stack.viewContext)
            note.id = UUID()
            note.title = "Batch \(i)"
            note.createdAt = Date()
        }
        try stack.save(stack.viewContext)

        let deletedCount = try stack.batchDelete(TestNote.self, in: stack.viewContext)
        XCTAssertEqual(deletedCount, 4)
        XCTAssertTrue(try stack.fetch(TestNote.self, in: stack.viewContext).isEmpty)
    }

    func testBatchDeleteWithPredicate() throws {
        let stack = try makeStack(storeType: .inMemory)
        for i in 0..<4 {
            let note = stack.create(TestNote.self, in: stack.viewContext)
            note.id = UUID()
            note.title = i % 2 == 0 ? "Even" : "Odd"
            note.createdAt = Date()
        }
        try stack.save(stack.viewContext)

        let deletedCount = try stack.batchDelete(
            TestNote.self,
            predicate: NSPredicate(format: "title == %@", "Even"),
            in: stack.viewContext
        )
        XCTAssertEqual(deletedCount, 2)
        XCTAssertEqual(try stack.count(TestNote.self, in: stack.viewContext), 2)
    }

    func testBatchDeleteSQLiteStore() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let stack = try makeStack(storeType: .sqlite, storeURL: tempURL)
        for i in 0..<3 {
            let note = stack.create(TestNote.self, in: stack.viewContext)
            note.id = UUID()
            note.title = "Disk \(i)"
            note.createdAt = Date()
        }
        try stack.save(stack.viewContext)

        let deletedCount = try stack.batchDelete(TestNote.self, in: stack.viewContext)
        XCTAssertEqual(deletedCount, 3)
    }

    // MARK: - Background tasks

    func testPerformBackgroundTask() async throws {
        let stack = try makeStack()
        let title = try await stack.performBackgroundTask { context -> String in
            let note = stack.create(TestNote.self, in: context)
            note.id = UUID()
            note.title = "Background"
            note.createdAt = Date()
            try context.save()
            return note.title
        }
        XCTAssertEqual(title, "Background")
        XCTAssertEqual(try stack.fetch(TestNote.self, in: stack.viewContext).count, 1)
    }

    // MARK: - Save

    func testSaveWithNoChangesIsNoOp() throws {
        let stack = try makeStack()
        XCTAssertNoThrow(try stack.save(stack.viewContext))
    }
}
