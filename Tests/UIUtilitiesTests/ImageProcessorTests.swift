//
//  ImageProcessorTests.swift
//  SwiftUtils
//

#if canImport(UIKit)
import XCTest
@testable import SwiftUtilsUIUtilities

final class ImageProcessorTests: XCTestCase {

    // MARK: - Helpers

    private func makeImage(size: CGSize, color: UIColor = .red) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Resizing

    func testResizedExactMatchesTargetSize() {
        let image = makeImage(size: CGSize(width: 100, height: 50))
        let resized = image.resized(to: CGSize(width: 40, height: 40), mode: .exact)
        XCTAssertEqual(resized?.size, CGSize(width: 40, height: 40))
    }

    func testResizedAspectFitMatchesTargetSize() {
        let image = makeImage(size: CGSize(width: 200, height: 100))
        let resized = image.resized(to: CGSize(width: 50, height: 50), mode: .aspectFit)
        // Canvas is always the target size; the image is letterboxed within it.
        XCTAssertEqual(resized?.size, CGSize(width: 50, height: 50))
    }

    func testResizedAspectFillMatchesTargetSize() {
        let image = makeImage(size: CGSize(width: 200, height: 100))
        let resized = image.resized(to: CGSize(width: 60, height: 60), mode: .aspectFill)
        XCTAssertEqual(resized?.size, CGSize(width: 60, height: 60))
    }

    func testResizedReturnsNilForZeroSize() {
        let image = makeImage(size: CGSize(width: 10, height: 10))
        XCTAssertNil(image.resized(to: .zero))
    }

    // MARK: - Cropping

    func testCroppedToRectProducesExpectedPixelSize() {
        let image = makeImage(size: CGSize(width: 100, height: 100))
        let cropped = image.cropped(to: CGRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(cropped?.size.width, 40, accuracy: 0.5)
        XCTAssertEqual(cropped?.size.height, 30, accuracy: 0.5)
    }

    func testCroppedToCircleProducesSquareCanvas() {
        let image = makeImage(size: CGSize(width: 80, height: 40))
        let circular = image.croppedToCircle()
        XCTAssertEqual(circular?.size.width, circular?.size.height)
        XCTAssertEqual(circular?.size.width, 40)
    }

    // MARK: - Rounding & Tinting

    func testRoundedPreservesSize() {
        let image = makeImage(size: CGSize(width: 60, height: 60))
        let rounded = image.rounded(radius: 12)
        XCTAssertEqual(rounded?.size, image.size)
    }

    func testTintedPreservesSize() {
        let image = makeImage(size: CGSize(width: 30, height: 30))
        let tinted = image.tinted(with: .blue)
        XCTAssertEqual(tinted?.size, image.size)
    }

    // MARK: - Compression

    func testCompressedJPEGDataStaysUnderLimit() {
        let image = makeImage(size: CGSize(width: 500, height: 500))
        let maxBytes = 20_000
        let data = image.compressedJPEGData(maxSizeInBytes: maxBytes)
        XCTAssertNotNil(data)
        if let data {
            XCTAssertLessThanOrEqual(data.count, maxBytes + 2_000) // small tolerance for binary search convergence
        }
    }

    func testCompressedJPEGDataReturnsNonNilEvenForTinyLimit() {
        let image = makeImage(size: CGSize(width: 200, height: 200))
        let data = image.compressedJPEGData(maxSizeInBytes: 1)
        XCTAssertNotNil(data)
    }

    // MARK: - Orientation

    func testNormalizedOrientationReturnsUpOrientation() {
        let image = makeImage(size: CGSize(width: 20, height: 20))
        let normalized = image.normalizedOrientation()
        XCTAssertEqual(normalized.imageOrientation, .up)
        XCTAssertEqual(normalized.size, image.size)
    }

    // MARK: - Downsampling

    func testDownsampledFromDataProducesBoundedSize() {
        let source = makeImage(size: CGSize(width: 400, height: 200))
        guard let data = source.pngData() else {
            return XCTFail("Failed to encode source image")
        }
        let thumbnail = UIImage.downsampled(from: data, to: CGSize(width: 50, height: 50), scale: 1)
        XCTAssertNotNil(thumbnail)
        if let thumbnail {
            XCTAssertLessThanOrEqual(thumbnail.size.width, 100)
            XCTAssertLessThanOrEqual(thumbnail.size.height, 100)
        }
    }

    func testDownsampledFromInvalidDataReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(UIImage.downsampled(from: garbage, to: CGSize(width: 50, height: 50), scale: 1))
    }

    func testDownsampledFromURL() throws {
        let source = makeImage(size: CGSize(width: 300, height: 300))
        guard let data = source.pngData() else {
            return XCTFail("Failed to encode source image")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = UIImage.downsampled(from: url, to: CGSize(width: 60, height: 60), scale: 1)
        XCTAssertNotNil(thumbnail)
    }
}
#endif
