import XCTest
@testable import SwiftUtilsStorage

/// An in-memory fake conforming to `CloudKeyValueStoring`, used so tests never touch
/// the real `NSUbiquitousKeyValueStore` (which requires an iCloud entitlement and a
/// signed-in account that aren't available in a test environment).
final class FakeCloudStore: CloudKeyValueStoring {
    private(set) var storage: [String: Any] = [:]
    private(set) var synchronizeCallCount = 0

    func object(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }

    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    @discardableResult
    func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }

    var dictionaryRepresentation: [String: Any] {
        storage
    }
}

final class CloudKeyValueStoreTests: XCTestCase {

    private var store: FakeCloudStore!

    override func setUp() {
        super.setUp()
        store = FakeCloudStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - CloudStorage (primitives)

    func testBoolDefaultValue() {
        let wrapper = CloudStorage<Bool>("flag", defaultValue: false, store: store)
        XCTAssertFalse(wrapper.wrappedValue)
    }

    func testBoolSetAndGet() {
        var wrapper = CloudStorage<Bool>("flag", defaultValue: false, store: store)
        wrapper.wrappedValue = true
        XCTAssertTrue(wrapper.wrappedValue)
    }

    func testIntSetAndGet() {
        var wrapper = CloudStorage<Int>("count", defaultValue: 0, store: store)
        wrapper.wrappedValue = 42
        XCTAssertEqual(wrapper.wrappedValue, 42)
    }

    func testDoubleSetAndGet() {
        var wrapper = CloudStorage<Double>("ratio", defaultValue: 0.0, store: store)
        wrapper.wrappedValue = 3.14
        XCTAssertEqual(wrapper.wrappedValue, 3.14, accuracy: 0.0001)
    }

    func testStringSetAndGet() {
        var wrapper = CloudStorage<String>("units", defaultValue: "metric", store: store)
        XCTAssertEqual(wrapper.wrappedValue, "metric")
        wrapper.wrappedValue = "imperial"
        XCTAssertEqual(wrapper.wrappedValue, "imperial")
    }

    func testDataSetAndGet() {
        var wrapper = CloudStorage<Data>("blob", defaultValue: Data(), store: store)
        let payload = "hello".data(using: .utf8)!
        wrapper.wrappedValue = payload
        XCTAssertEqual(wrapper.wrappedValue, payload)
    }

    func testRemoveRevertsToDefault() {
        var wrapper = CloudStorage<String>("units", defaultValue: "metric", store: store)
        wrapper.wrappedValue = "imperial"
        XCTAssertEqual(wrapper.wrappedValue, "imperial")

        wrapper.remove()
        XCTAssertEqual(wrapper.wrappedValue, "metric")
    }

    func testIsSet() {
        var wrapper = CloudStorage<Int>("count", defaultValue: 0, store: store)
        XCTAssertFalse(wrapper.isSet)

        wrapper.wrappedValue = 5
        XCTAssertTrue(wrapper.isSet)

        wrapper.remove()
        XCTAssertFalse(wrapper.isSet)
    }

    func testWriteCallsSynchronize() {
        var wrapper = CloudStorage<Int>("count", defaultValue: 0, store: store)
        wrapper.wrappedValue = 1
        XCTAssertEqual(store.synchronizeCallCount, 1)
    }

    // MARK: - CloudCodableStorage

    func testCodableDefaultValue() {
        struct Settings: Codable, Equatable { var theme: String; var scale: Double }
        let defaultValue = Settings(theme: "system", scale: 1.0)
        let wrapper = CloudCodableStorage<Settings>("settings", defaultValue: defaultValue, store: store)
        XCTAssertEqual(wrapper.wrappedValue, defaultValue)
    }

    func testCodableSetAndGet() {
        struct Settings: Codable, Equatable { var theme: String; var scale: Double }
        var wrapper = CloudCodableStorage<Settings>(
            "settings", defaultValue: Settings(theme: "system", scale: 1.0), store: store
        )
        wrapper.wrappedValue = Settings(theme: "dark", scale: 1.2)
        XCTAssertEqual(wrapper.wrappedValue, Settings(theme: "dark", scale: 1.2))
    }

    func testCodableRemove() {
        struct Settings: Codable, Equatable { var theme: String; var scale: Double }
        let defaultValue = Settings(theme: "system", scale: 1.0)
        var wrapper = CloudCodableStorage<Settings>("settings", defaultValue: defaultValue, store: store)
        wrapper.wrappedValue = Settings(theme: "dark", scale: 1.2)
        wrapper.remove()
        XCTAssertEqual(wrapper.wrappedValue, defaultValue)
    }

    // MARK: - CloudKeyValueObserver.ChangeReason

    func testChangeReasonMapsServerChange() {
        let reason = CloudKeyValueObserver.ChangeReason(rawValue: NSUbiquitousKeyValueStoreServerChange)
        XCTAssertEqual(reason, .serverChange)
    }

    func testChangeReasonMapsInitialSyncChange() {
        let reason = CloudKeyValueObserver.ChangeReason(rawValue: NSUbiquitousKeyValueStoreInitialSyncChange)
        XCTAssertEqual(reason, .initialSyncChange)
    }

    func testChangeReasonMapsQuotaViolation() {
        let reason = CloudKeyValueObserver.ChangeReason(rawValue: NSUbiquitousKeyValueStoreQuotaViolationChange)
        XCTAssertEqual(reason, .quotaViolationChange)
    }

    func testChangeReasonMapsAccountChange() {
        let reason = CloudKeyValueObserver.ChangeReason(rawValue: NSUbiquitousKeyValueStoreAccountChange)
        XCTAssertEqual(reason, .accountChange)
    }

    func testChangeReasonMapsUnknownForNil() {
        let reason = CloudKeyValueObserver.ChangeReason(rawValue: nil)
        XCTAssertEqual(reason, .unknown)
    }
}
