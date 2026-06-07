import XCTest
@testable import SwiftUtilsStorage

final class FileManagerHelperTests: XCTestCase {

    var helper: FileManagerHelper!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        helper = FileManagerHelper()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var customDir: FileDirectory { .custom(tempDir) }

    // MARK: - Write & Read Codable

    func testWriteAndReadCodable() throws {
        struct Profile: Codable, Equatable {
            let name: String
            let age: Int
        }
        let profile = Profile(name: "Pawan", age: 30)
        try helper.write(profile, to: "profile.json", in: customDir)
        let loaded: Profile = try helper.read(from: "profile.json", in: customDir)
        XCTAssertEqual(profile, loaded)
    }

    func testOverwriteFalseThrowsWhenFileExists() throws {
        let data = "hello".data(using: .utf8)!
        try helper.writeData(data, to: "file.dat", in: customDir)
        XCTAssertThrowsError(
            try helper.writeData(data, to: "file.dat", in: customDir, overwrite: false)
        ) { error in
            guard case FileManagerError.fileAlreadyExists = error else {
                XCTFail("Expected fileAlreadyExists, got \(error)")
                return
            }
        }
    }

    func testOverwriteTrueReplacesFile() throws {
        try helper.writeData("v1".data(using: .utf8)!, to: "ver.txt", in: customDir)
        try helper.writeData("v2".data(using: .utf8)!, to: "ver.txt", in: customDir, overwrite: true)
        let result = try helper.readData(from: "ver.txt", in: customDir)
        XCTAssertEqual(String(data: result, encoding: .utf8), "v2")
    }

    // MARK: - Raw Data

    func testWriteAndReadData() throws {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try helper.writeData(original, to: "bytes.bin", in: customDir)
        let result = try helper.readData(from: "bytes.bin", in: customDir)
        XCTAssertEqual(original, result)
    }

    func testReadDataThrowsForMissingFile() {
        XCTAssertThrowsError(try helper.readData(from: "missing.bin", in: customDir)) { error in
            guard case FileManagerError.fileNotFound = error else {
                XCTFail("Expected fileNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Existence

    func testExistsReturnsFalseBeforeWrite() throws {
        XCTAssertFalse(try helper.exists("ghost.json", in: customDir))
    }

    func testExistsReturnsTrueAfterWrite() throws {
        try helper.writeData(Data(), to: "empty.json", in: customDir)
        XCTAssertTrue(try helper.exists("empty.json", in: customDir))
    }

    // MARK: - Attributes

    func testAttributesReturnsSize() throws {
        let content = "Hello, Swift!".data(using: .utf8)!
        try helper.writeData(content, to: "attrs.txt", in: customDir)
        let attrs = try helper.attributes(of: "attrs.txt", in: customDir)
        XCTAssertEqual(attrs.size, content.count)
        XCTAssertNotNil(attrs.creationDate)
        XCTAssertNotNil(attrs.modificationDate)
    }

    func testAttributesThrowsForMissingFile() {
        XCTAssertThrowsError(try helper.attributes(of: "nope.txt", in: customDir)) { error in
            guard case FileManagerError.fileNotFound = error else {
                XCTFail("Expected fileNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Directory listing

    func testContentsOfDirectoryReturnsWrittenFiles() throws {
        try helper.writeData(Data(), to: "a.json", in: customDir)
        try helper.writeData(Data(), to: "b.json", in: customDir)
        let urls = try helper.contentsOfDirectory(customDir)
        let names = urls.map { $0.lastPathComponent }.sorted()
        XCTAssertEqual(names, ["a.json", "b.json"])
    }

    // MARK: - Create subdirectory

    func testCreateDirectoryCreatesSubdirectory() throws {
        let subURL = try helper.createDirectory(named: "logs", in: customDir)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: subURL.path, isDirectory: &isDir)
        XCTAssertTrue(exists && isDir.boolValue)
    }

    // MARK: - Delete

    func testDeleteRemovesFile() throws {
        try helper.writeData(Data(), to: "todelete.txt", in: customDir)
        try helper.delete("todelete.txt", in: customDir)
        XCTAssertFalse(try helper.exists("todelete.txt", in: customDir))
    }

    func testDeleteIsNoOpForMissingFile() {
        XCTAssertNoThrow(try helper.delete("nonexistent.txt", in: customDir))
    }

    // MARK: - Clear directory

    func testClearDirectoryRemovesAllItems() throws {
        try helper.writeData(Data(), to: "x.txt", in: customDir)
        try helper.writeData(Data(), to: "y.txt", in: customDir)
        try helper.clearDirectory(customDir)
        let urls = try helper.contentsOfDirectory(customDir)
        XCTAssertTrue(urls.isEmpty)
    }

    // MARK: - Move

    func testMoveFileToAnotherDirectory() throws {
        let destDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destDir) }

        try helper.writeData("data".data(using: .utf8)!, to: "move_me.txt", in: customDir)
        try helper.move("move_me.txt", from: customDir, to: .custom(destDir))

        XCTAssertFalse(try helper.exists("move_me.txt", in: customDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("move_me.txt").path))
    }

    // MARK: - Copy

    func testCopyFileToAnotherDirectory() throws {
        let destDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destDir) }

        try helper.writeData("original".data(using: .utf8)!, to: "source.txt", in: customDir)
        try helper.copy("source.txt", from: customDir, to: .custom(destDir), newFilename: "copy.txt")

        XCTAssertTrue(try helper.exists("source.txt", in: customDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("copy.txt").path))
    }
}
