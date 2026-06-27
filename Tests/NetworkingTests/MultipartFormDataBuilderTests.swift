import XCTest
@testable import SwiftUtilsNetworking

final class MultipartFormDataBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func bodyString(_ builder: MultipartFormDataBuilder) -> String {
        String(data: builder.build(), encoding: .utf8) ?? ""
    }

    // MARK: - Content-Type / Boundary

    func testContentTypeIncludesBoundary() {
        let builder = MultipartFormDataBuilder(boundary: "TestBoundary123")
        XCTAssertEqual(builder.contentType, "multipart/form-data; boundary=TestBoundary123")
    }

    func testDefaultBoundariesAreUnique() {
        let first = MultipartFormDataBuilder()
        let second = MultipartFormDataBuilder()
        XCTAssertNotEqual(first.boundary, second.boundary)
    }

    func testBodyEndsWithClosingBoundary() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        builder.addField(name: "a", value: "1")
        XCTAssertTrue(bodyString(builder).hasSuffix("--B1--\r\n"))
    }

    // MARK: - Text Fields

    func testAddFieldProducesExpectedPart() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        builder.addField(name: "title", value: "Vacation Photo")

        let expected = "--B1\r\n" +
            "Content-Disposition: form-data; name=\"title\"\r\n" +
            "\r\n" +
            "Vacation Photo\r\n" +
            "--B1--\r\n"
        XCTAssertEqual(bodyString(builder), expected)
    }

    func testMultipleFieldsAppearInOrder() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        builder
            .addField(name: "title", value: "Vacation Photo")
            .addField(name: "userId", value: "42")

        let body = bodyString(builder)
        let titleRange = body.range(of: "name=\"title\"")
        let userIdRange = body.range(of: "name=\"userId\"")

        XCTAssertNotNil(titleRange)
        XCTAssertNotNil(userIdRange)
        XCTAssertTrue(titleRange!.lowerBound < userIdRange!.lowerBound)
    }

    // MARK: - File Parts (in-memory)

    func testAddFileProducesExpectedHeaders() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        let data = Data("fake-image-bytes".utf8)
        builder.addFile(name: "photo", fileName: "beach.jpg", mimeType: "image/jpeg", data: data)

        let body = bodyString(builder)
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"photo\"; filename=\"beach.jpg\"\r\n"))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg\r\n"))
        XCTAssertTrue(body.contains("fake-image-bytes"))
    }

    func testAddFileDefaultMimeType() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        builder.addFile(name: "blob", fileName: "data.bin", data: Data([0x01, 0x02]))
        XCTAssertTrue(bodyString(builder).contains("Content-Type: application/octet-stream\r\n"))
    }

    func testChainingReturnsSameBuilder() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        let result = builder
            .addField(name: "a", value: "1")
            .addFile(name: "b", fileName: "f.txt", mimeType: "text/plain", data: Data("x".utf8))
        XCTAssertTrue(result === builder)
    }

    // MARK: - File Parts (from disk)

    func testAddFileFromURLReadsContentsAndGuessesMimeType() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{\"a\":1}".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let builder = MultipartFormDataBuilder(boundary: "B1")
        try builder.addFile(name: "payload", fileURL: tempURL)

        let body = bodyString(builder)
        XCTAssertTrue(body.contains("filename=\"\(tempURL.lastPathComponent)\""))
        XCTAssertTrue(body.contains("Content-Type: application/json\r\n"))
        XCTAssertTrue(body.contains("{\"a\":1}"))
    }

    func testAddFileFromMissingURLThrows() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-missing.dat")
        let builder = MultipartFormDataBuilder(boundary: "B1")

        XCTAssertThrowsError(try builder.addFile(name: "f", fileURL: missingURL)) { error in
            guard case MultipartFormDataBuilder.BuilderError.fileReadFailed(let url, _) = error else {
                XCTFail("Expected fileReadFailed, got \(error)")
                return
            }
            XCTAssertEqual(url, missingURL)
        }
    }

    // MARK: - JSON Parts

    func testAddJSONEncodesValueAsFilePart() throws {
        struct Payload: Codable, Equatable { let id: Int; let name: String }
        let builder = MultipartFormDataBuilder(boundary: "B1")
        let payload = Payload(id: 1, name: "Ada")
        try builder.addJSON(name: "metadata", value: payload)

        let body = bodyString(builder)
        XCTAssertTrue(body.contains("name=\"metadata\"; filename=\"metadata.json\""))
        XCTAssertTrue(body.contains("Content-Type: application/json\r\n"))

        // Extract the JSON segment between the headers and the closing CRLF, then
        // round-trip decode it rather than asserting on raw key ordering.
        guard let jsonStart = body.range(of: "\r\n\r\n", range: body.range(of: "metadata.json")!.upperBound..<body.endIndex) else {
            XCTFail("Could not locate JSON body segment")
            return
        }
        let remainder = body[jsonStart.upperBound...]
        guard let jsonEnd = remainder.range(of: "\r\n--B1") else {
            XCTFail("Could not locate end of JSON body segment")
            return
        }
        let jsonString = String(remainder[remainder.startIndex..<jsonEnd.lowerBound])
        let decoded = try JSONDecoder().decode(Payload.self, from: Data(jsonString.utf8))
        XCTAssertEqual(decoded, payload)
    }

    func testAddJSONPropagatesEncodingErrors() {
        struct Unencodable: Encodable {
            func encode(to encoder: Encoder) throws {
                throw NSError(domain: "test", code: 1)
            }
        }
        let builder = MultipartFormDataBuilder(boundary: "B1")
        XCTAssertThrowsError(try builder.addJSON(name: "bad", value: Unencodable())) { error in
            guard case MultipartFormDataBuilder.BuilderError.jsonEncodingFailed = error else {
                XCTFail("Expected jsonEncodingFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - apply(to:)

    func testApplySetsHeadersAndBody() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        builder.addField(name: "a", value: "1")

        var request = URLRequest(url: URL(string: "https://example.com/upload")!)
        builder.apply(to: &request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "\(builder.build().count)")
        XCTAssertEqual(request.httpBody, builder.build())
    }

    func testBuildIsIdempotent() {
        let builder = MultipartFormDataBuilder(boundary: "B1")
        builder.addField(name: "a", value: "1")
        XCTAssertEqual(builder.build(), builder.build())
    }

    // MARK: - MIME Type Lookup

    func testMimeTypeForKnownExtensions() {
        XCTAssertEqual(MultipartFormDataBuilder.mimeType(forPathExtension: "jpg"), "image/jpeg")
        XCTAssertEqual(MultipartFormDataBuilder.mimeType(forPathExtension: "JPEG"), "image/jpeg")
        XCTAssertEqual(MultipartFormDataBuilder.mimeType(forPathExtension: "png"), "image/png")
        XCTAssertEqual(MultipartFormDataBuilder.mimeType(forPathExtension: "pdf"), "application/pdf")
        XCTAssertEqual(MultipartFormDataBuilder.mimeType(forPathExtension: "mp4"), "video/mp4")
    }

    func testMimeTypeForUnknownExtensionFallsBackToOctetStream() {
        XCTAssertEqual(MultipartFormDataBuilder.mimeType(forPathExtension: "xyz"), "application/octet-stream")
    }

    // MARK: - URLRequest Convenience

    func testURLRequestMultipartFormDataConvenience() {
        let url = URL(string: "https://example.com/upload")!
        let request = URLRequest.multipartFormData(url: url) { form in
            form.addField(name: "userId", value: "42")
            form.addFile(name: "avatar", fileName: "me.jpg", mimeType: "image/jpeg", data: Data("bytes".utf8))
        }

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNotNil(request.httpBody)

        let bodyText = String(data: request.httpBody!, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyText.contains("name=\"userId\""))
        XCTAssertTrue(bodyText.contains("filename=\"me.jpg\""))
    }
}
