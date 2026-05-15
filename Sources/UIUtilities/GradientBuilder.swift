//
//  GradientBuilder.swift
//  SwiftUtils
//
//  A declarative gradient builder for UIKit and SwiftUI.
//  Supports linear, radial, and angular gradients with chainable configuration.
//  Target: iOS 15+ / Swift 5.9+
//

#if canImport(UIKit)
import UIKit

// MARK: - GradientStop

/// A single color stop in a gradient, defined by a `UIColor` and a normalized location (0…1).
public struct GradientStop: Sendable {
    /// The color at this stop.
    public let color: UIColor
    /// The position of this stop along the gradient axis, in the range 0…1.
    public let location: CGFloat

    /// Creates a gradient stop.
    /// - Parameters:
    ///   - color: The color at this stop.
    ///   - location: The normalized position (0 = start, 1 = end). Clamped to 0…1.
    public init(color: UIColor, location: CGFloat) {
        self.color = color
        self.location = min(max(location, 0), 1)
    }
}

// MARK: - GradientDirection

/// Predefined directions for linear gradients.
public enum GradientDirection: Sendable {
    case topToBottom
    case bottomToTop
    case leftToRight
    case rightToLeft
    case topLeftToBottomRight
    case topRightToBottomLeft
    case bottomLeftToTopRight
    case bottomRightToTopLeft
    /// A custom direction defined by start and end points in unit-coordinate space (0…1).
    case custom(start: CGPoint, end: CGPoint)

    /// The start point in unit-coordinate space.
    public var startPoint: CGPoint {
        switch self {
        case .topToBottom:            return CGPoint(x: 0.5, y: 0)
        case .bottomToTop:            return CGPoint(x: 0.5, y: 1)
        case .leftToRight:            return CGPoint(x: 0, y: 0.5)
        case .rightToLeft:            return CGPoint(x: 1, y: 0.5)
        case .topLeftToBottomRight:   return CGPoint(x: 0, y: 0)
        case .topRightToBottomLeft:   return CGPoint(x: 1, y: 0)
        case .bottomLeftToTopRight:   return CGPoint(x: 0, y: 1)
        case .bottomRightToTopLeft:   return CGPoint(x: 1, y: 1)
        case .custom(let start, _):   return start
        }
    }

    /// The end point in unit-coordinate space.
    public var endPoint: CGPoint {
        switch self {
        case .topToBottom:            return CGPoint(x: 0.5, y: 1)
        case .bottomToTop:            return CGPoint(x: 0.5, y: 0)
        case .leftToRight:            return CGPoint(x: 1, y: 0.5)
        case .rightToLeft:            return CGPoint(x: 0, y: 0.5)
        case .topLeftToBottomRight:   return CGPoint(x: 1, y: 1)
        case .topRightToBottomLeft:   return CGPoint(x: 0, y: 1)
        case .bottomLeftToTopRight:   return CGPoint(x: 1, y: 0)
        case .bottomRightToTopLeft:   return CGPoint(x: 0, y: 0)
        case .custom(_, let end):     return end
        }
    }
}

// MARK: - GradientStyle

/// The style of gradient to render.
public enum GradientStyle: Sendable {
    /// A linear gradient along the specified direction.
    case linear(GradientDirection)
    /// A radial gradient expanding from `center` to `radius` (in unit-coordinate space).
    case radial(center: CGPoint, radius: CGFloat)
}

// MARK: - GradientBuilder

/// A chainable builder for creating `CAGradientLayer` instances with a declarative API.
///
/// ```swift
/// let gradient = GradientBuilder()
///     .add(color: .systemBlue, at: 0)
///     .add(color: .systemPurple, at: 0.5)
///     .add(color: .systemPink, at: 1)
///     .direction(.topLeftToBottomRight)
///     .cornerRadius(16)
///     .build(in: CGRect(x: 0, y: 0, width: 300, height: 200))
/// ```
public final class GradientBuilder {
    private var stops: [GradientStop] = []
    private var style: GradientStyle = .linear(.topToBottom)
    private var layerCornerRadius: CGFloat = 0

    /// Creates a new, empty gradient builder.
    public init() {}

    // MARK: - Configuration

    /// Adds a color stop to the gradient.
    /// - Parameters:
    ///   - color: The color at this position.
    ///   - location: The normalized position along the gradient axis (0…1).
    /// - Returns: `self` for chaining.
    @discardableResult
    public func add(color: UIColor, at location: CGFloat) -> GradientBuilder {
        stops.append(GradientStop(color: color, location: location))
        return self
    }

    /// Sets the gradient direction for linear gradients.
    /// - Parameter direction: The desired direction.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func direction(_ direction: GradientDirection) -> GradientBuilder {
        self.style = .linear(direction)
        return self
    }

    /// Configures a radial gradient.
    /// - Parameters:
    ///   - center: The center point in unit-coordinate space (default: (0.5, 0.5)).
    ///   - radius: The radius in unit-coordinate space (default: 0.5).
    /// - Returns: `self` for chaining.
    @discardableResult
    public func radial(center: CGPoint = CGPoint(x: 0.5, y: 0.5), radius: CGFloat = 0.5) -> GradientBuilder {
        self.style = .radial(center: center, radius: radius)
        return self
    }

    /// Sets the corner radius of the gradient layer.
    /// - Parameter radius: The corner radius in points.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func cornerRadius(_ radius: CGFloat) -> GradientBuilder {
        self.layerCornerRadius = radius
        return self
    }

    // MARK: - Building

    /// Builds a `CAGradientLayer` with the configured stops and style.
    /// - Parameter frame: The frame for the gradient layer.
    /// - Returns: A configured `CAGradientLayer`.
    public func build(in frame: CGRect) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = frame
        layer.cornerRadius = layerCornerRadius

        let sortedStops = stops.sorted { $0.location < $1.location }
        layer.colors = sortedStops.map { $0.color.cgColor }
        layer.locations = sortedStops.map { NSNumber(value: Double($0.location)) }

        switch style {
        case .linear(let direction):
            layer.type = .axial
            layer.startPoint = direction.startPoint
            layer.endPoint = direction.endPoint

        case .radial(let center, let radius):
            layer.type = .radial
            layer.startPoint = center
            layer.endPoint = CGPoint(x: center.x + radius, y: center.y + radius)
        }

        return layer
    }

    /// Renders the gradient into a `UIImage`.
    /// - Parameter size: The size of the output image.
    /// - Returns: A `UIImage` containing the gradient, or `nil` if rendering fails.
    public func renderImage(size: CGSize) -> UIImage? {
        let layer = build(in: CGRect(origin: .zero, size: size))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}

// MARK: - UIView Extension

public extension UIView {
    /// Applies a gradient as the view's background.
    ///
    /// Removes any previously applied gradient (identified by the name `"GradientBuilder.backgroundGradient"`).
    ///
    /// - Parameter builder: A configured `GradientBuilder`.
    /// - Returns: The created `CAGradientLayer` for further customization if needed.
    @discardableResult
    func applyGradient(_ builder: GradientBuilder) -> CAGradientLayer {
        // Remove existing gradient
        layer.sublayers?
            .filter { $0.name == "GradientBuilder.backgroundGradient" }
            .forEach { $0.removeFromSuperlayer() }

        let gradientLayer = builder.build(in: bounds)
        gradientLayer.name = "GradientBuilder.backgroundGradient"
        layer.insertSublayer(gradientLayer, at: 0)
        return gradientLayer
    }
}

// MARK: - Preset Gradients

public extension GradientBuilder {
    /// A warm sunset gradient (orange → red → purple).
    static var sunset: GradientBuilder {
        GradientBuilder()
            .add(color: UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1), at: 0)
            .add(color: UIColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1), at: 0.5)
            .add(color: UIColor(red: 0.5, green: 0.1, blue: 0.6, alpha: 1), at: 1)
            .direction(.topLeftToBottomRight)
    }

    /// An ocean gradient (light blue → deep blue).
    static var ocean: GradientBuilder {
        GradientBuilder()
            .add(color: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1), at: 0)
            .add(color: UIColor(red: 0.0, green: 0.3, blue: 0.7, alpha: 1), at: 1)
            .direction(.topToBottom)
    }

    /// A forest gradient (light green → dark green).
    static var forest: GradientBuilder {
        GradientBuilder()
            .add(color: UIColor(red: 0.4, green: 0.9, blue: 0.4, alpha: 1), at: 0)
            .add(color: UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1), at: 1)
            .direction(.topToBottom)
    }

    /// A night sky gradient (dark blue → indigo → black).
    static var nightSky: GradientBuilder {
        GradientBuilder()
            .add(color: UIColor(red: 0.05, green: 0.05, blue: 0.2, alpha: 1), at: 0)
            .add(color: UIColor(red: 0.15, green: 0.1, blue: 0.4, alpha: 1), at: 0.5)
            .add(color: UIColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1), at: 1)
            .direction(.topToBottom)
    }
}
#endif
