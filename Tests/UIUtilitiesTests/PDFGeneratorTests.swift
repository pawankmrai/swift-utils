//
//  PDFGeneratorTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
import PDFKit
@testable import SwiftUtilsUIUtilities

final class PDFGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private func makeImage(size: CGSize, color: UIColor = .blue) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    // MARK: - Empty Content

    func testGenerateThrowsOnEmptyContent() {
        let generator = PDFGenerator()
        XCTAssertThrowsError(try generator.generate()) { error in
            XCTAssertEqual(error as? PDFGeneratorError, .emptyContent)
        }
    }

    // MARK: - Basic Generation

    func testGenerateProducesValidPDFData() throws {
        let generator = PDFGenerator().addText("Hello, PDF!")
        let data = try generator.generate()
        XCTAssertFalse(data.isEmpty)
        XCTAssertNotNil(PDFDocument(data: data))
    }

    func testGenerateSinglePageForShortContent() throws {
        let generator = PDFGenerator()
            .addText("Invoice #1042", font: .boldSystemFont(ofSize: 20))
            .addSpacing(12)
            .addText("Thank you for your purchase.")
        let data = try generator.generate()
        XCTAssertEqual(pageCount(of: data), 1)
    }

    // MARK: - Page Sizes

    func testUsLetterPageDimensions() throws {
        let generator = PDFGenerator(pageSize: .usLetter).addText("Letter")
        let data = try generator.generate()
        let page = PDFDocument(data: data)?.page(at: 0)
        XCTAssertEqual(page?.bounds(for: .mediaBox).width, 612, accuracy: 0.5)
        XCTAssertEqual(page?.bounds(for: .mediaBox).height, 792, accuracy: 0.5)
    }

    func testA4PageDimensions() throws {
        let generator = PDFGenerator(pageSize: .a4).addText("A4")
        let data = try generator.generate()
        let page = PDFDocument(data: data)?.page(at: 0)
        XCTAssertEqual(page?.bounds(for: .mediaBox).width, 595, accuracy: 0.5)
        XCTAssertEqual(page?.bounds(for: .mediaBox).height, 842, accuracy: 0.5)
    }

    func testCustomPageDimensions() throws {
        let generator = PDFGenerator(pageSize: .custom(width: 300, height: 400)).addText("Custom")
        let data = try generator.generate()
        let page = PDFDocument(data: data)?.page(at: 0)
        XCTAssertEqual(page?.bounds(for: .mediaBox).width, 300, accuracy: 0.5)
        XCTAssertEqual(page?.bounds(for: .mediaBox).height, 400, accuracy: 0.5)
    }

    // MARK: - Pagination

    func testAddPageBreakForcesAdditionalPage() throws {
        let generator = PDFGenerator()
            .addText("Page one")
            .addPageBreak()
            .addText("Page two")
        let data = try generator.generate()
        XCTAssertEqual(pageCount(of: data), 2)
    }

    func testLongTextFlowsAcrossMultiplePages() throws {
        let longText = Array(repeating: "This is a line of invoice content that repeats many times. ", count: 400).joined()
        let generator = PDFGenerator().addText(longText)
        let data = try generator.generate()
        XCTAssertGreaterThan(pageCount(of: data), 1)
    }

    func testImageTallerThanPageDoesNotCrashOrLoop() throws {
        let tallImage = makeImage(size: CGSize(width: 100, height: 4000))
        let generator = PDFGenerator().addImage(tallImage)
        XCTAssertNoThrow(try generator.generate())
    }

    // MARK: - Images

    func testImageIsScaledToContentWidth() throws {
        let square = makeImage(size: CGSize(width: 400, height: 400))
        let generator = PDFGenerator(margins: .standard).addImage(square)
        let data = try generator.generate()
        XCTAssertEqual(pageCount(of: data), 1)
    }

    func testImageRespectsMaxHeight() throws {
        let wide = makeImage(size: CGSize(width: 1000, height: 100))
        let generator = PDFGenerator().addImage(wide, maxHeight: 40)
        XCTAssertNoThrow(try generator.generate())
    }

    // MARK: - Attributed Text

    func testAddAttributedTextIsIncluded() throws {
        let attributed = NSAttributedString(string: "Styled", attributes: [.font: UIFont.italicSystemFont(ofSize: 14)])
        let generator = PDFGenerator().addAttributedText(attributed)
        let data = try generator.generate()
        XCTAssertTrue(PDFDocument(data: data)?.string?.contains("Styled") ?? false)
    }

    // MARK: - Metadata

    func testMetadataIsEmbeddedInDocument() throws {
        let metadata = PDFMetadata(title: "Test Title", author: "Pawan", subject: "Unit Test")
        let generator = PDFGenerator(metadata: metadata).addText("Body")
        let data = try generator.generate()
        let attributes = PDFDocument(data: data)?.documentAttributes
        XCTAssertEqual(attributes?[PDFDocumentAttribute.titleAttribute] as? String, "Test Title")
        XCTAssertEqual(attributes?[PDFDocumentAttribute.authorAttribute] as? String, "Pawan")
    }

    // MARK: - Reset & Reuse

    func testResetClearsQueuedContent() {
        let generator = PDFGenerator().addText("Will be cleared")
        generator.reset()
        XCTAssertThrowsError(try generator.generate())
    }

    func testGeneratorCanBeReusedAfterGenerate() throws {
        let generator = PDFGenerator().addText("First document")
        _ = try generator.generate()
        generator.reset()
        generator.addText("Second document")
        let data = try generator.generate()
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - Chaining

    func testMethodsReturnSelfForChaining() {
        let generator = PDFGenerator()
        let result = generator
            .addText("a")
            .addSpacing(4)
            .addPageBreak()
            .addAttributedText(NSAttributedString(string: "b"))

        XCTAssertTrue(result === generator)
    }

    // MARK: - Write to Disk

    func testWriteToURLCreatesReadableFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        let generator = PDFGenerator().addText("Written to disk")
        try generator.write(to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let readBack = try Data(contentsOf: url)
        XCTAssertNotNil(PDFDocument(data: readBack))
    }
}
#endif
