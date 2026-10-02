import XCTest
import CryptoKit
@testable import SwiftUtilsStorage

final class EncryptedFileStoreTests: XCTestCase {

    private struct Profile: Codable, Equatable {
        let name: String
        let email: String
    }

    private var directory: URL!
    private var keyProvider: InMemoryKeyProvider!
    private var store: EncryptedFileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        keyProvider = InMemoryKeyProvider()
        store = try EncryptedFileStore(directory: directory, keyProvider: keyProvider)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveAndLoadRoundTrip() throws {
        let profile = Profile(name: "Pawan", email: "p@example.com")
        try store.save(profile, forKey: "profile")
        XCTAssertEqual(try store.load(Profile.self, forKey: "profile"), profile)
    }

    func testLoadMissingKeyReturnsNil() throws {
        XCTAssertNil(try store.load(Profile.self, forKey: "missing"))
    }

    func testFileContentsAreNotPlaintext() throws {
        try store.save("super-secret-token", forKey: "token")
        let raw = try Data(contentsOf: store.fileURL(for: "token"))
        XCTAssertNil(raw.range(of: Data("super-secret-token".utf8)))
    }

    func testFileNameDoesNotLeakKey() {
        let url = store.fileURL(for: "auth/refresh token")
        XCTAssertFalse(url.lastPathComponent.contains("refresh"))
        XCTAssertEqual(url.pathExtension, "enc")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    }

    func testOverwriteReplacesValue() throws {
        try store.save(1, forKey: "count")
        try store.save(2, forKey: "count")
        XCTAssertEqual(try store.load(Int.self, forKey: "count"), 2)
    }

    func testWrongKeyThrowsDecryptionFailed() throws {
        try store.save("hello", forKey: "greeting")
        let other = try EncryptedFileStore(directory: directory, keyProvider: InMemoryKeyProvider())
        XCTAssertThrowsError(try other.load(String.self, forKey: "greeting")) { error in
            XCTAssertEqual(error as? EncryptedFileStoreError, .decryptionFailed)
        }
    }

    func testTamperedFileThrowsDecryptionFailed() throws {
        try store.save("hello", forKey: "greeting")
        let url = store.fileURL(for: "greeting")
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: url)
        XCTAssertThrowsError(try store.load(String.self, forKey: "greeting")) { error in
            XCTAssertEqual(error as? EncryptedFileStoreError, .decryptionFailed)
        }
    }

    func testSameKeyAcrossInstancesCanDecrypt() throws {
        try store.save([1, 2, 3], forKey: "numbers")
        let reopened = try EncryptedFileStore(directory: directory, keyProvider: keyProvider)
        XCTAssertEqual(try reopened.load([Int].self, forKey: "numbers"), [1, 2, 3])
    }

    func testContainsAndRemove() throws {
        XCTAssertFalse(store.contains("flag"))
        try store.save(true, forKey: "flag")
        XCTAssertTrue(store.contains("flag"))
        try store.remove(forKey: "flag")
        XCTAssertFalse(store.contains("flag"))
        XCTAssertNoThrow(try store.remove(forKey: "flag"))
    }

    func testRemoveAllDeletesOnlyStoreFiles() throws {
        try store.save("a", forKey: "a")
        try store.save("b", forKey: "b")
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)

        try store.removeAll()

        XCTAssertFalse(store.contains("a"))
        XCTAssertFalse(store.contains("b"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testEncryptionIsNonDeterministic() throws {
        try store.save("same", forKey: "x")
        let first = try Data(contentsOf: store.fileURL(for: "x"))
        try store.save("same", forKey: "x")
        let second = try Data(contentsOf: store.fileURL(for: "x"))
        XCTAssertNotEqual(first, second, "Each seal should use a fresh nonce")
    }
}
