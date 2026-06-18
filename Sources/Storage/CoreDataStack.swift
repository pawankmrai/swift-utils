import CoreData

/// Errors thrown by `CoreDataStack`.
public enum CoreDataStackError: LocalizedError {
    /// No `NSManagedObjectModel` could be resolved for the given name/bundle.
    case modelNotFound(String)
    /// The persistent store failed to load.
    case loadFailed(Error)
    /// `NSManagedObjectContext.save()` failed.
    case saveFailed(Error)
    /// A fetch request failed.
    case fetchFailed(Error)
    /// A batch delete request failed.
    case batchDeleteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):  return "No managed object model named \(name) could be found."
        case .loadFailed(let e):        return "Failed to load persistent store: \(e.localizedDescription)"
        case .saveFailed(let e):        return "Failed to save context: \(e.localizedDescription)"
        case .fetchFailed(let e):       return "Fetch request failed: \(e.localizedDescription)"
        case .batchDeleteFailed(let e): return "Batch delete failed: \(e.localizedDescription)"
        }
    }
}

/// A lightweight, generic wrapper around `NSPersistentContainer` that adds
/// typed fetch/save/delete helpers, an async background-task bridge, and an
/// in-memory mode for SwiftUI previews and unit tests.
///
/// `CoreDataStack` accepts any `NSManagedObjectModel`, including one built
/// entirely in code, so it works in Swift packages and test targets that
/// have no `.xcdatamodeld` file.
///
/// ## Quick start
/// ```swift
/// let stack = try CoreDataStack(modelName: "Model")
/// let note = stack.create(Note.self, in: stack.viewContext)
/// note.title = "Hello"
/// try stack.save(stack.viewContext)
///
/// let all = try stack.fetch(Note.self, in: stack.viewContext)
/// ```
public final class CoreDataStack {

    /// Underlying storage backend for the persistent container.
    public enum StoreType {
        /// On-disk store — durable across launches.
        case sqlite
        /// In-memory store — ideal for SwiftUI previews and unit tests.
        case inMemory
    }

    /// The underlying `NSPersistentContainer`.
    public let container: NSPersistentContainer

    /// The backend this stack was configured with.
    public let storeType: StoreType

    /// The main-thread context, suitable for UI binding.
    public var viewContext: NSManagedObjectContext { container.viewContext }

    /// Loads a persistent container for `modelName`.
    ///
    /// - Parameters:
    ///   - modelName: Name passed to `NSPersistentContainer`; also used to locate a compiled
    ///     `.momd` file in `bundle` when `model` is nil.
    ///   - model: An explicit model (e.g. built in code with `NSEntityDescription`). When supplied,
    ///     bundle lookup is skipped entirely.
    ///   - storeType: `.sqlite` for durable storage, `.inMemory` for ephemeral storage.
    ///   - storeURL: Optional explicit file location for a `.sqlite` store. Ignored for `.inMemory`.
    ///   - bundle: The bundle to search for the compiled model when `model` is nil.
    public init(
        modelName: String,
        model: NSManagedObjectModel? = nil,
        storeType: StoreType = .sqlite,
        storeURL: URL? = nil,
        bundle: Bundle = .main
    ) throws {
        let resolvedModel: NSManagedObjectModel
        if let model {
            resolvedModel = model
        } else if let url = bundle.url(forResource: modelName, withExtension: "momd"),
                  let loaded = NSManagedObjectModel(contentsOf: url) {
            resolvedModel = loaded
        } else if let merged = NSManagedObjectModel.mergedModel(from: [bundle]) {
            resolvedModel = merged
        } else {
            throw CoreDataStackError.modelNotFound(modelName)
        }

        self.storeType = storeType
        container = NSPersistentContainer(name: modelName, managedObjectModel: resolvedModel)

        if storeType == .inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else if let storeURL {
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw CoreDataStackError.loadFailed(loadError)
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Creates a new background context whose changes merge automatically into `viewContext`.
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    /// Runs `block` on a background context and returns its result, bridging
    /// Core Data's queue-confined API into async/await.
    public func performBackgroundTask<T>(
        _ block: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = newBackgroundContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    continuation.resume(returning: try block(context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Saves `context` if — and only if — it has uncommitted changes.
    public func save(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            throw CoreDataStackError.saveFailed(error)
        }
    }

    /// Inserts and returns a new, unsaved instance of `T` in `context`.
    public func create<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) -> T {
        NSEntityDescription.insertNewObject(forEntityName: String(describing: T.self), into: context) as! T
    }

    /// Fetches every `T` matching `predicate`, optionally sorted and capped at `limit`.
    public func fetch<T: NSManagedObject>(
        _ type: T.Type,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil,
        in context: NSManagedObjectContext
    ) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: T.self))
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        if let limit { request.fetchLimit = limit }
        do {
            return try context.fetch(request)
        } catch {
            throw CoreDataStackError.fetchFailed(error)
        }
    }

    /// Returns the number of `T` entities matching `predicate`, without loading them into memory.
    public func count<T: NSManagedObject>(
        _ type: T.Type,
        predicate: NSPredicate? = nil,
        in context: NSManagedObjectContext
    ) throws -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: T.self))
        request.predicate = predicate
        do {
            return try context.count(for: request)
        } catch {
            throw CoreDataStackError.fetchFailed(error)
        }
    }

    /// Deletes a single managed object and immediately saves the context.
    public func delete(_ object: NSManagedObject, in context: NSManagedObjectContext) throws {
        context.delete(object)
        try save(context)
    }

    /// Deletes every `T` matching `predicate` and returns the number of objects removed.
    ///
    /// Uses `NSBatchDeleteRequest` for `.sqlite` stores, which deletes directly in the
    /// persistent store without loading objects into memory. `.inMemory` stores don't
    /// support batch requests, so this falls back to a fetch-then-delete loop.
    @discardableResult
    public func batchDelete<T: NSManagedObject>(
        _ type: T.Type,
        predicate: NSPredicate? = nil,
        in context: NSManagedObjectContext
    ) throws -> Int {
        switch storeType {
        case .inMemory:
            let objects = try fetch(T.self, predicate: predicate, in: context)
            objects.forEach(context.delete)
            try save(context)
            return objects.count

        case .sqlite:
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: T.self))
            request.predicate = predicate
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                let ids = result?.result as? [NSManagedObjectID] ?? []
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                    into: [viewContext, context]
                )
                return ids.count
            } catch {
                throw CoreDataStackError.batchDeleteFailed(error)
            }
        }
    }
}
