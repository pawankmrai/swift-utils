//
//  ImageProcessor.swift
//  SwiftUtils
//
//  Memory-efficient UIImage resizing, cropping, and compression utilities.
//  Includes ImageIO-backed downsampling for loading large images (e.g. camera
//  photos) without decoding them at full resolution first.
//  Target: iOS 15+ / Swift 5.9+
//

#if canImport(UIKit)
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - ImageResizeMode

/// Strategies for fitting an image into a target size.
public enum ImageResizeMode: Sendable {
    /// Scales the image to fit entirely within the target size, preserving aspect ratio.
    case aspectFit
    /// Scales the image to fill the target size, preserving aspect ratio and cropping overflow.
    case aspectFill
    /// Stretches the image to exactly match the target size, ignoring aspect ratio.
    case exact
}

// MARK: - UIImage Processing

public extension UIImage {

    /// Resizes the image to `size` using the given resize mode.
    /// - Parameters:
    ///   - size: The target size in points.
    ///   - mode: The scaling strategy. Defaults to `.aspectFit`.
    /// - Returns: A new resized `UIImage`, or `nil` if rendering fails.
    func resized(to size: CGSize, mode: ImageResizeMode = .aspectFit) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let drawRect: CGRect
        switch mode {
        case .exact:
            drawRect = CGRect(origin: .zero, size: size)
        case .aspectFit:
            let scale = min(size.width / self.size.width, size.height / self.size.height)
            let fitted = CGSize(width: self.size.width * scale, height: self.size.height * scale)
            drawRect = CGRect(
                x: (size.width - fitted.width) / 2,
                y: (size.height - fitted.height) / 2,
                width: fitted.width,
                height: fitted.height
            )
        case .aspectFill:
            let scale = max(size.width / self.size.width, size.height / self.size.height)
            let filled = CGSize(width: self.size.width * scale, height: self.size.height * scale)
            drawRect = CGRect(
                x: (size.width - filled.width) / 2,
                y: (size.height - filled.height) / 2,
                width: filled.width,
                height: filled.height
            )
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: drawRect)
        }
    }

    /// Crops the image to `rect`, expressed in the image's own pixel coordinate space.
    /// - Parameter rect: The region to crop, in pixels (not points).
    /// - Returns: A cropped `UIImage` preserving the original scale and orientation, or `nil` if the crop fails.
    func cropped(to rect: CGRect) -> UIImage? {
        guard let cgImage = cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }

    /// Masks the image to a circle, cropping to a centered square first if needed.
    /// - Returns: A circular `UIImage` with a transparent background, or `nil` if rendering fails.
    func croppedToCircle() -> UIImage? {
        let side = min(size.width, size.height)
        let square = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: square, format: format)
        return renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: square)).addClip()
            let origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
            self.draw(in: CGRect(origin: origin, size: size))
        }
    }

    /// Returns a copy of the image with rounded corners.
    /// - Parameter radius: The corner radius in points.
    /// - Returns: A new `UIImage` with rounded corners, or `nil` if rendering fails.
    func rounded(radius: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            self.draw(in: rect)
        }
    }

    /// Recolors the non-transparent pixels of the image to a single flat color,
    /// preserving the original alpha mask. Useful for template/icon tinting.
    /// - Parameter color: The tint color to apply.
    /// - Returns: A tinted `UIImage`, or `nil` if rendering fails.
    func tinted(with color: UIColor) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            let rect = CGRect(origin: .zero, size: size)
            context.fill(rect)
            self.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }

    /// Iteratively compresses the image to JPEG data at or below `maxSizeInBytes`,
    /// binary-searching the quality factor.
    /// - Parameters:
    ///   - maxSizeInBytes: The target maximum size, in bytes.
    ///   - initialQuality: The starting compression quality (0...1). Defaults to `0.9`.
    /// - Returns: JPEG `Data` at or under the target size, or the smallest achievable
    ///   representation if the target cannot be met even at minimum quality. `nil` if encoding fails entirely.
    func compressedJPEGData(maxSizeInBytes: Int, initialQuality: CGFloat = 0.9) -> Data? {
        var quality = initialQuality
        var data = jpegData(compressionQuality: quality)
        var lowerBound: CGFloat = 0
        var upperBound: CGFloat = quality

        guard var bestData = data else { return nil }

        for _ in 0..<8 {
            guard let currentData = data else { break }
            if currentData.count <= maxSizeInBytes {
                bestData = currentData
                lowerBound = quality
                if upperBound - lowerBound < 0.01 { break }
                quality = (quality + upperBound) / 2
            } else {
                upperBound = quality
                quality = (quality + lowerBound) / 2
            }
            data = jpegData(compressionQuality: quality)
        }

        return bestData
    }

    /// Normalizes the image's pixel orientation to `.up`, redrawing it if necessary.
    /// Useful before pixel-level processing that ignores EXIF orientation.
    /// - Returns: An orientation-corrected `UIImage`.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Memory-efficient thumbnail generation from image `Data` using ImageIO.
    ///
    /// Unlike `UIImage(data:).resized(to:)`, this never decodes the source image at full
    /// resolution — ImageIO downsamples during decode, making it dramatically cheaper for
    /// large photos (e.g. camera captures) when only a small thumbnail is needed.
    ///
    /// - Parameters:
    ///   - data: The encoded source image data (JPEG, PNG, HEIC, etc.).
    ///   - pointSize: The desired thumbnail size, in points.
    ///   - scale: The screen scale to render at. Defaults to `UIScreen.main.scale`.
    /// - Returns: A downsampled `UIImage`, or `nil` if the data cannot be decoded.
    static func downsampled(from data: Data, to pointSize: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Convenience overload that downsamples an image directly from disk without loading
    /// the full file into memory first.
    /// - Parameters:
    ///   - url: The file URL of the source image.
    ///   - pointSize: The desired thumbnail size, in points.
    ///   - scale: The screen scale to render at. Defaults to `UIScreen.main.scale`.
    /// - Returns: A downsampled `UIImage`, or `nil` if the file cannot be decoded.
    static func downsampled(from url: URL, to pointSize: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
#endif
