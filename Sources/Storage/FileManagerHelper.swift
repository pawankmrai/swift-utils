import Foundation

/// A namespace for common file system directories.
public enum FileDirectory {
    /// `<app>/Documents` — user-visible, backed up by iCloud.
    case documents
    /// `<app>/Library/Caches` — not backed up; OS may purge when storage is low.
    case caches
    /// `<app>/tmp` — purged between launches; use for short-lived scratch files.
    case temporary
    /// `<app>/Library/Application Support` — backed up; not user-visible.
    case applicationSupport
    /// A custom absolute directory URL you supply.
    case custom(URL)

    /// Resolves the URL for this directory, creating it if needed.
    public func url() throws -> URL {
        switch self {
        case .documents:
            return try FileManagerHelper.resolveSearchPath(.documentDirectory)
        case .caches:
            return try FileManagerHelper.resolveSearchPath(.cachesDirectory)
        case .temporary:
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        case .applicationSupport:
            return try FileManagerHelper.resolveSearchPath(.applicationSupportDirectory)
        case .custom(let url):
            return url
        }
    }
}

/// Errors thrown by `FileManagerHelper`.
public enum FileManagerError: LocalizedError {
    case directoryNotFound(String)
    case fileNotFound(URL)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileAlreadyExists(URL)
    case underlyingError(Error)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path): return "Directory not found: \(path)"
        case .fileNotFound(let url):        return "File not found: \(url.path)"
        case .encodingFailed(let e):        return "Encoding failed: \(e.localizedDescription)"
        case .decodingFailed(let e):        return "Decoding failed: \(e.localizedDescription)"
        case .fileAlreadyExists(let url):   return "File already exists: \(url.path)"
        case .underlyingError(let e):       return e.localizedDescription
        }
    }
}

/// A lightweight helper that wraps `FileManager` with a clean, typed API for
/// reading, writing, listing, copying, and moving files in the standard iOS
/// sandbox directories.
///
/// ## Quick start
/// ```swift
/// let helper = FileManagerHelper()
/// try helper.write(myModel, to: "profile.json", in: .documents)
/// let loaded: MyModel = try helper.read(from: "profile.json", in: .documents)
/// let urls = try helper.contentsOfDirectory(.caches)
/// ```
public struct FileManagerHelper {

    private let fm: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a helper using the shared `FileManager` and standard JSON coders.
    public init(
        fileManager: FileManager = .default,
        encoder: JSONEncoder = {
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
        }(),
        decoder: JSONDecoder = {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
        }()
    ) {
        self.fm = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Directory helpers

    /// Returns the resolved URL for a `FileDirectory`, creating it if needed.
    public func directoryURL(for directory: FileDirectory) throws -> URL {
        let url = try directory.url()
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Creates a subdirectory inside the given `FileDirectory`.
    @discardableResult
    public func createDirectory(named name: String, in directory: FileDirectory) throws -> URL {
        let parent = try directoryURL(for: directory)
        let target = parent.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    // MARK: - Write

    /// Encodes a `Codable` value as JSON and writes it to `filename` inside `directory`.
    public func write<T: Encodable>(
        _ value: T,
        to filename: String,
        in directory: FileDirectory,
        overwrite: Bool = true
    ) throws {
        let url = try fileURL(filename, in: directory)
        if !overwrite && fm.fileExists(atPath: url.path) {
            throw FileManagerError.fileAlreadyExists(url)
        }
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch let err as EncodingError {
            throw FileManagerError.encodingFailed(err)
        } catch {
            throw FileManagerError.underlyingError(error)
        }
    }

    /// Writes raw `Data` to `filename` inside `directory`.
    public func writeData(
        _ data: Data,
        to filename: String,
        in directory: FileDirectory,
        overwrite: Bool = true
    ) throws {
        let url = try fileURL(filename, in: directory)
        if !overwrite && fm.fileExists(atPath: url.path) {
            throw FileManagerError.fileAlreadyExists(url)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw FileManagerError.underlyingError(error)
        }
    }

    // MARK: - Read

    /// Reads and decodes a `Codable` value from `filename` in `directory`.
    public func read<T: Decodable>(from filename: String, in directory: FileDirectory) throws -> T {
        let url = try fileURL(filename, in: directory)
        guard fm.fileExists(atPath: url.path) else { throw FileManagerError.fileNotFound(url) }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch let err as DecodingError {
            throw FileManagerError.decodingFailed(err)
        } catch {
            throw FileManagerError.underlyingError(error)
        }
    }

    /// Reads raw `Data` from `filename` in `directory`.
    public func readData(from filename: String, in directory: FileDirectory) throws -> Data {
        let url = try fileURL(filename, in: directory)
        guard fm.fileExists(atPath: url.path) else { throw FileManagerError.fileNotFound(url) }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileManagerError.underlyingError(error)
        }
    }

    // MARK: - Existence & metadata

    /// Returns `true` if a file or directory exists at `filename` in `directory`.
    public func exists(_ filename: String, in directory: FileDirectory) throws -> Bool {
        let url = try fileURL(filename, in: directory)
        return fm.fileExists(atPath: url.path)
    }

    /// Returns file attributes (size, creation date, modification date) for `filename`.
    public func attributes(of filename: String, in directory: FileDirectory) throws -> FileAttributes {
        let url = try fileURL(filename, in: directory)
        guard fm.fileExists(atPath: url.path) else { throw FileManagerError.fileNotFound(url) }
        do {
            let raw = try fm.attributesOfItem(atPath: url.path)
            return FileAttributes(
                size: raw[.size] as? Int ?? 0,
                creationDate: raw[.creationDate] as? Date,
                modificationDate: raw[.modificationDate] as? Date
            )
        } catch {
            throw FileManagerError.underlyingError(error)
        }
    }

    // MARK: - List

    /// Returns URLs of all items directly inside `directory` (non-recursive).
    public func contentsOfDirectory(_ directory: FileDirectory) throws -> [URL] {
        let url = try directoryURL(for: directory)
        do {
            return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            throw FileManagerError.underlyingError(error)
        }
    }

    // MARK: - Move / Copy / Delete

    /// Moves `filename` from `source` to `destination`, optionally renaming it.
    public func move(
        _ filename: String,
        from source: FileDirectory,
        to destination: FileDirectory,
        newFilename: String? = nil
    ) throws {
        let srcURL = try fileURL(filename, in: source)
        let dstURL = try fileURL(newFilename ?? filename, in: destination)
        guard fm.fileExists(atPath: srcURL.path) else { throw FileManagerError.fileNotFound(srcURL) }
        do { try fm.moveItem(at: srcURL, to: dstURL) } catch { throw FileManagerError.underlyingError(error) }
    }

    /// Copies `filename` from `source` into `destination`, optionally renaming it.
    public func copy(
        _ filename: String,
        from source: FileDirectory,
        to destination: FileDirectory,
        newFilename: String? = nil
    ) throws {
        let srcURL = try fileURL(filename, in: source)
        let dstURL = try fileURL(newFilename ?? filename, in: destination)
        guard fm.fileExists(atPath: srcURL.path) else { throw FileManagerError.fileNotFound(srcURL) }
        do { try fm.copyItem(at: srcURL, to: dstURL) } catch { throw FileManagerError.underlyingError(error) }
    }

    /// Deletes the file at `filename` in `directory`. No-op if the file doesn't exist.
    public func delete(_ filename: String, in directory: FileDirectory) throws {
        let url = try fileURL(filename, in: directory)
        guard fm.fileExists(atPath: url.path) else { return }
        do { try fm.removeItem(at: url) } catch { throw FileManagerError.underlyingError(error) }
    }

    /// Removes all files and subdirectories inside `directory` without removing the directory itself.
    public func clearDirectory(_ directory: FileDirectory) throws {
        let urls = try contentsOfDirectory(directory)
        for url in urls {
            do { try fm.removeItem(at: url) } catch { throw FileManagerError.underlyingError(error) }
        }
    }

    // MARK: - Internals

    private func fileURL(_ filename: String, in directory: FileDirectory) throws -> URL {
        let base = try directoryURL(for: directory)
        return base.appendingPathComponent(filename)
    }

    static func resolveSearchPath(_ path: FileManager.SearchPathDirectory) throws -> URL {
        guard let url = FileManager.default.urls(for: path, in: .userDomainMask).first else {
            throw FileManagerError.directoryNotFound(String(describing: path))
        }
        return url
    }
}

// MARK: - Supporting types

/// Basic metadata for a file.
public struct FileAttributes {
    /// Size in bytes.
    public let size: Int
    /// When the file was created.
    public let creationDate: Date?
    /// When the file was last modified.
    public let modificationDate: Date?
}
