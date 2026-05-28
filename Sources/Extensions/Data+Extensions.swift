import Foundation
import CommonCrypto

// MARK: - Hex Encoding

extension Data {
    
    /// Creates `Data` from a hexadecimal string.
    ///
    /// Accepts both upper- and lowercase hex characters with optional `0x` prefix.
    ///
    /// ```swift
    /// let data = Data(hex: "48656C6C6F")
    /// ```
    ///
    /// - Parameter hex: A hexadecimal encoded string.
    /// - Returns: `nil` if the string contains invalid hex characters or has an odd length.
    public init?(hex: String) {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
    
    /// Returns a lowercase hexadecimal string representation.
    ///
    /// ```swift
    /// let hex = myData.hexString  // "48656c6c6f"
    /// ```
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
    
    /// Returns an uppercase hexadecimal string representation.
    public var hexStringUppercased: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

// MARK: - Base64 URL-Safe Encoding

extension Data {
    
    /// Returns a URL-safe Base64 encoded string (RFC 4648 §5).
    ///
    /// Replaces `+` with `-`, `/` with `_`, and strips trailing `=` padding.
    ///
    /// ```swift
    /// let token = payload.base64URLEncoded  // "eyJhbGciOi..."
    /// ```
    public var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Creates `Data` from a URL-safe Base64 encoded string.
    ///
    /// Re-adds padding and restores standard Base64 characters before decoding.
    ///
    /// - Parameter base64URL: A URL-safe Base64 encoded string.
    /// - Returns: `nil` if the string is not valid Base64.
    public init?(base64URLEncoded base64URL: String) {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        
        self.init(base64Encoded: base64)
    }
}

// MARK: - Hashing

extension Data {
    
    /// SHA-256 hash of the data.
    ///
    /// ```swift
    /// let hash = myData.sha256
    /// print(hash.hexString)
    /// ```
    public var sha256: Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(count), &digest)
        }
        return Data(digest)
    }
    
    /// MD5 hash of the data.
    ///
    /// - Note: MD5 is not cryptographically secure. Use for checksums or cache keys only.
    public var md5: Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(count), &digest)
        }
        return Data(digest)
    }
}

// MARK: - UTF-8 String Conversion

extension Data {
    
    /// Interprets the data as a UTF-8 encoded string, returning `nil` on failure.
    ///
    /// ```swift
    /// if let text = responseData.utf8String {
    ///     print(text)
    /// }
    /// ```
    public var utf8String: String? {
        String(data: self, encoding: .utf8)
    }
    
    /// Creates `Data` from a UTF-8 string.
    ///
    /// ```swift
    /// let data = Data(utf8: "Hello, world!")
    /// ```
    public init(utf8 string: String) {
        self = Data(string.utf8)
    }
}

// MARK: - Pretty Print for JSON

extension Data {
    
    /// Returns the data pretty-printed as a JSON string, or `nil` if not valid JSON.
    ///
    /// ```swift
    /// if let json = responseData.prettyJSON {
    ///     print(json)
    /// }
    /// ```
    public var prettyJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }
}

// MARK: - Byte Helpers

extension Data {
    
    /// A human-readable file-size string (e.g., "2.4 MB").
    ///
    /// Uses binary units (1 KB = 1024 bytes) matching Apple's convention.
    ///
    /// ```swift
    /// let size = imageData.readableByteCount  // "1.2 MB"
    /// ```
    public var readableByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
    
    /// Returns a new `Data` with the bytes reversed.
    public var reversed: Data {
        Data(self.reversed() as [UInt8])
    }
    
    /// Returns a slice of data from the given range, clamped to valid bounds.
    ///
    /// ```swift
    /// let header = data.safeSlice(0..<4)
    /// ```
    ///
    /// - Parameter range: The desired byte range.
    /// - Returns: The sliced data, or empty data if the range is out of bounds.
    public func safeSlice(_ range: Range<Int>) -> Data {
        let lower = Swift.max(range.lowerBound, 0)
        let upper = Swift.min(range.upperBound, count)
        guard lower < upper else { return Data() }
        return self[lower..<upper]
    }
}

// MARK: - Compression (zlib)

@available(iOS 13.0, macOS 10.15, *)
extension Data {
    
    /// Compresses the data using the specified algorithm.
    ///
    /// ```swift
    /// let compressed = try originalData.compressed(using: .zlib)
    /// ```
    ///
    /// - Parameter algorithm: The compression algorithm (default `.zlib`).
    /// - Returns: The compressed data.
    /// - Throws: An error if compression fails.
    public func compressed(using algorithm: NSData.CompressionAlgorithm = .zlib) throws -> Data {
        try (self as NSData).compressed(using: algorithm) as Data
    }
    
    /// Decompresses the data using the specified algorithm.
    ///
    /// ```swift
    /// let original = try compressedData.decompressed(using: .zlib)
    /// ```
    ///
    /// - Parameter algorithm: The compression algorithm (default `.zlib`).
    /// - Returns: The decompressed data.
    /// - Throws: An error if decompression fails.
    public func decompressed(using algorithm: NSData.CompressionAlgorithm = .zlib) throws -> Data {
        try (self as NSData).decompressed(using: algorithm) as Data
    }
}
