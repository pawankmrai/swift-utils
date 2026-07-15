import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(UIKit)
import UIKit
#endif

// MARK: - QRCodeCorrectionLevel

/// Error-correction level for generated QR codes, trading payload robustness
/// against visual density. Higher levels tolerate more damage/occlusion
/// (useful when overlaying a logo) at the cost of a denser pattern.
public enum QRCodeCorrectionLevel: String, Sendable, CaseIterable {
    /// ~7% of codewords can be restored.
    case low = "L"
    /// ~15% of codewords can be restored.
    case medium = "M"
    /// ~25% of codewords can be restored.
    case quartile = "Q"
    /// ~30% of codewords can be restored. Recommended when overlaying a logo.
    case high = "H"
}

// MARK: - QRCodeGeneratorError

/// Errors surfaced while generating a QR code.
public enum QRCodeGeneratorError: Error, Sendable, Equatable {
    /// The payload was empty or could not be encoded as UTF-8 data.
    case emptyPayload
    /// The underlying `CIFilter(name: "CIQRCodeGenerator")` is unavailable on this platform.
    case filterUnavailable
    /// Core Image failed to render the filter output to a bitmap.
    case renderingFailed
}

// MARK: - QRCodeGenerator

/// Generates crisp, non-interpolated QR code images from text, URLs, or raw
/// data using Core Image, so you don't have to hand-roll `CIFilter` plumbing
/// or worry about the default output being blurry when scaled up.
///
/// ```swift
/// let cgImage = try QRCodeGenerator.generate(from: "https://swift.org", scale: 12)
/// imageView.image = UIImage(cgImage: cgImage)
/// ```
public enum QRCodeGenerator {

    /// Renders a QR code for `payload` and returns it as a `CGImage`.
    ///
    /// The filter's native output is a 1-point-per-module bitmap; this method
    /// scales it up with nearest-neighbor sampling so edges stay sharp instead
    /// of anti-aliased, which keeps the code scannable.
    ///
    /// - Parameters:
    ///   - payload: The raw bytes to encode. Typically UTF-8 text, a URL string, or a vCard/Wi-Fi payload.
    ///   - correctionLevel: Error-correction level. Defaults to `.medium`.
    ///   - scale: Integer scale factor applied to the native module bitmap. Defaults to `10`.
    /// - Throws: `QRCodeGeneratorError` if the payload is empty or rendering fails.
    /// - Returns: A `CGImage` containing the QR code, in device pixels.
    public static func generate(
        from payload: Data,
        correctionLevel: QRCodeCorrectionLevel = .medium,
        scale: CGFloat = 10
    ) throws -> CGImage {
        guard !payload.isEmpty else { throw QRCodeGeneratorError.emptyPayload }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = payload
        filter.correctionLevel = correctionLevel.rawValue

        guard let outputImage = filter.outputImage else {
            throw QRCodeGeneratorError.filterUnavailable
        }

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw QRCodeGeneratorError.renderingFailed
        }
        return cgImage
    }

    /// Convenience overload that encodes `string` as UTF-8 before generating.
    ///
    /// - SeeAlso: `generate(from:correctionLevel:scale:)` (`Data` overload)
    public static func generate(
        from string: String,
        correctionLevel: QRCodeCorrectionLevel = .medium,
        scale: CGFloat = 10
    ) throws -> CGImage {
        guard let data = string.data(using: .utf8) else { throw QRCodeGeneratorError.emptyPayload }
        return try generate(from: data, correctionLevel: correctionLevel, scale: scale)
    }

    #if canImport(UIKit)
    /// Renders a QR code as a `UIImage`, optionally recoloring the foreground/background.
    ///
    /// - Parameters:
    ///   - string: The text to encode.
    ///   - correctionLevel: Error-correction level. Defaults to `.medium`.
    ///   - scale: Integer scale factor. Defaults to `10`.
    ///   - foregroundColor: Color of the modules ("pixels"). Defaults to black.
    ///   - backgroundColor: Color behind the modules. Defaults to white.
    /// - Returns: A `UIImage` ready to drop into a `UIImageView` or SwiftUI `Image`.
    public static func generateImage(
        from string: String,
        correctionLevel: QRCodeCorrectionLevel = .medium,
        scale: CGFloat = 10,
        foregroundColor: UIColor = .black,
        backgroundColor: UIColor = .white
    ) throws -> UIImage {
        let cgImage = try generate(from: string, correctionLevel: correctionLevel, scale: scale)
        let baseImage = UIImage(cgImage: cgImage)

        guard foregroundColor != .black || backgroundColor != .white else { return baseImage }

        let renderer = UIGraphicsImageRenderer(size: baseImage.size)
        return renderer.image { _ in
            let ciImage = CIImage(cgImage: cgImage)
            let colorFilter = CIFilter.falseColor()
            colorFilter.inputImage = ciImage
            colorFilter.color0 = CIColor(color: foregroundColor)
            colorFilter.color1 = CIColor(color: backgroundColor)
            if let output = colorFilter.outputImage,
               let recolored = CIContext().createCGImage(output, from: output.extent) {
                UIImage(cgImage: recolored).draw(in: CGRect(origin: .zero, size: baseImage.size))
            } else {
                baseImage.draw(in: CGRect(origin: .zero, size: baseImage.size))
            }
        }
    }
    #endif

    // MARK: - Payload builders

    /// Builds a standard `WIFI:` payload string that, when scanned, offers to
    /// join a Wi-Fi network without exposing the password as plain text on screen.
    ///
    /// - Parameters:
    ///   - ssid: The network name.
    ///   - password: The network password. Pass `nil` for open networks.
    ///   - security: The security protocol string, e.g. `"WPA"`, `"WEP"`, or `"nopass"`.
    ///   - isHidden: Whether the network is hidden (not broadcasting its SSID).
    public static func wifiPayload(
        ssid: String,
        password: String?,
        security: String = "WPA",
        isHidden: Bool = false
    ) -> String {
        func escape(_ value: String) -> String {
            var result = value
            for character in ["\\", ";", ",", ":", "\""] {
                result = result.replacingOccurrences(of: character, with: "\\\(character)")
            }
            return result
        }
        let passwordField = password.map { "P:\(escape($0));" } ?? ""
        return "WIFI:T:\(security);S:\(escape(ssid));\(passwordField)H:\(isHidden ? "true" : "false");;"
    }
}
