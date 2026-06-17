//
//  LayoutHelpers.swift
//  SwiftUtils
//
//  A fluent, chainable Auto Layout builder for UIKit: pin edges, center,
//  size, match dimensions, and set priorities without boilerplate.
//  Target: iOS 15+ / Swift 5.9+
//

#if canImport(UIKit)
import UIKit

// MARK: - LayoutEdges

/// A set of view edges to constrain, used by ``LayoutAnchorBuilder/pin(_:to:insets:)``.
public struct LayoutEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top = LayoutEdges(rawValue: 1 << 0)
    public static let leading = LayoutEdges(rawValue: 1 << 1)
    public static let trailing = LayoutEdges(rawValue: 1 << 2)
    public static let bottom = LayoutEdges(rawValue: 1 << 3)

    /// All four edges.
    public static let all: LayoutEdges = [.top, .leading, .trailing, .bottom]
    /// Leading and trailing.
    public static let horizontal: LayoutEdges = [.leading, .trailing]
    /// Top and bottom.
    public static let vertical: LayoutEdges = [.top, .bottom]
}

// MARK: - LayoutDimension

/// Identifies a sizing dimension for ``LayoutAnchorBuilder/match(_:of:multiplier:constant:)``.
public enum LayoutDimension: Sendable {
    case width
    case height
}

// MARK: - NSDirectionalEdgeInsets Convenience

public extension NSDirectionalEdgeInsets {
    /// Equal insets on all four edges.
    static func all(_ value: CGFloat) -> NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }

    /// Insets mirrored horizontally and vertically.
    static func symmetric(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}

// MARK: - LayoutAnchorProviding

/// A type that exposes the standard Auto Layout anchors.
///
/// Both `UIView` and `UILayoutGuide` already declare every anchor required
/// here, so conformance is free — this lets `LayoutAnchorBuilder` pin a view
/// to either a sibling view *or* a layout guide (such as `safeAreaLayoutGuide`
/// or `layoutMarginsGuide`) through a single, uniform API.
public protocol LayoutAnchorProviding {
    var topAnchor: NSLayoutYAxisAnchor { get }
    var bottomAnchor: NSLayoutYAxisAnchor { get }
    var leadingAnchor: NSLayoutXAxisAnchor { get }
    var trailingAnchor: NSLayoutXAxisAnchor { get }
    var centerXAnchor: NSLayoutXAxisAnchor { get }
    var centerYAnchor: NSLayoutYAxisAnchor { get }
    var widthAnchor: NSLayoutDimension { get }
    var heightAnchor: NSLayoutDimension { get }
}

extension UIView: LayoutAnchorProviding {}
extension UILayoutGuide: LayoutAnchorProviding {}

// MARK: - LayoutAnchorBuilder

/// A chainable builder for activating Auto Layout constraints on a single view.
///
/// Access it via the ``UIKit/UIView/layout`` property. All configuration
/// methods return `self` and build up a list of constraints that are only
/// created when a terminal method (`activate()` or `constraints()`) is called.
///
/// ```swift
/// let card = UIView()
/// container.addSubview(card)
/// card.layout
///     .pin(.horizontal, to: container, insets: .symmetric(horizontal: 16))
///     .pin(.top, to: container.safeAreaLayoutGuide, insets: .all(12))
///     .size(height: 120)
///     .activate()
/// ```
public final class LayoutAnchorBuilder {
    private let view: UIView
    private var constraints: [NSLayoutConstraint] = []

    init(view: UIView) {
        self.view = view
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Pins the given edges of the view to the matching edges of `other`.
    /// - Parameters:
    ///   - edges: Which edges to constrain (default: `.all`).
    ///   - other: The view or layout guide to pin against.
    ///   - insets: Directional insets applied to each pinned edge.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func pin(_ edges: LayoutEdges = .all, to other: LayoutAnchorProviding, insets: NSDirectionalEdgeInsets = .zero) -> LayoutAnchorBuilder {
        if edges.contains(.top) {
            constraints.append(view.topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top))
        }
        if edges.contains(.leading) {
            constraints.append(view.leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.leading))
        }
        if edges.contains(.trailing) {
            constraints.append(other.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: insets.trailing))
        }
        if edges.contains(.bottom) {
            constraints.append(other.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: insets.bottom))
        }
        return self
    }

    /// Centers the view within `other`, optionally offset.
    /// - Parameters:
    ///   - other: The view or layout guide to center within.
    ///   - offset: A point offset applied after centering (default: `.zero`).
    /// - Returns: `self` for chaining.
    @discardableResult
    public func center(in other: LayoutAnchorProviding, offset: CGPoint = .zero) -> LayoutAnchorBuilder {
        constraints.append(view.centerXAnchor.constraint(equalTo: other.centerXAnchor, constant: offset.x))
        constraints.append(view.centerYAnchor.constraint(equalTo: other.centerYAnchor, constant: offset.y))
        return self
    }

    /// Sets fixed-size constraints on the view.
    /// - Parameters:
    ///   - width: A fixed width in points, or `nil` to leave unconstrained.
    ///   - height: A fixed height in points, or `nil` to leave unconstrained.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func size(width: CGFloat? = nil, height: CGFloat? = nil) -> LayoutAnchorBuilder {
        if let width {
            constraints.append(view.widthAnchor.constraint(equalToConstant: width))
        }
        if let height {
            constraints.append(view.heightAnchor.constraint(equalToConstant: height))
        }
        return self
    }

    /// Constrains the view's aspect ratio (width ÷ height).
    /// - Parameter ratio: The desired width-to-height ratio, e.g. `16.0/9.0`.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func aspectRatio(_ ratio: CGFloat) -> LayoutAnchorBuilder {
        constraints.append(view.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: ratio))
        return self
    }

    /// Matches a dimension of the view to the same dimension of `other`.
    /// - Parameters:
    ///   - dimension: Which dimension to match.
    ///   - other: The view or layout guide to match against.
    ///   - multiplier: A scale factor applied to `other`'s dimension (default: `1`).
    ///   - constant: A constant offset added after scaling (default: `0`).
    /// - Returns: `self` for chaining.
    @discardableResult
    public func match(_ dimension: LayoutDimension, of other: LayoutAnchorProviding, multiplier: CGFloat = 1, constant: CGFloat = 0) -> LayoutAnchorBuilder {
        switch dimension {
        case .width:
            constraints.append(view.widthAnchor.constraint(equalTo: other.widthAnchor, multiplier: multiplier, constant: constant))
        case .height:
            constraints.append(view.heightAnchor.constraint(equalTo: other.heightAnchor, multiplier: multiplier, constant: constant))
        }
        return self
    }

    /// Applies a priority to every constraint configured so far in this chain.
    /// - Parameter priority: The layout priority to assign.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func priority(_ priority: UILayoutPriority) -> LayoutAnchorBuilder {
        constraints.forEach { $0.priority = priority }
        return self
    }

    /// Returns the configured constraints without activating them.
    public func constraints() -> [NSLayoutConstraint] {
        constraints
    }

    /// Activates all constraints configured so far.
    /// - Returns: The activated constraints, for storage if later deactivation is needed.
    @discardableResult
    public func activate() -> [NSLayoutConstraint] {
        NSLayoutConstraint.activate(constraints)
        return constraints
    }
}

// MARK: - UIView Convenience Extension

public extension UIView {
    /// Starts a chainable Auto Layout configuration for this view.
    ///
    /// Sets `translatesAutoresizingMaskIntoConstraints = false` as a side effect,
    /// since that is required for any of the resulting constraints to take effect.
    var layout: LayoutAnchorBuilder { LayoutAnchorBuilder(view: self) }

    /// Pins all (or selected) edges of this view to its superview in one call.
    /// - Parameters:
    ///   - edges: Which edges to pin (default: `.all`).
    ///   - insets: Directional insets applied to each pinned edge.
    /// - Returns: The activated constraints, or `nil` if the view has no superview.
    @discardableResult
    func pinToSuperview(_ edges: LayoutEdges = .all, insets: NSDirectionalEdgeInsets = .zero) -> [NSLayoutConstraint]? {
        guard let superview else { return nil }
        return layout.pin(edges, to: superview, insets: insets).activate()
    }

    /// Centers this view within its superview in one call.
    /// - Parameter offset: A point offset applied after centering (default: `.zero`).
    /// - Returns: The activated constraints, or `nil` if the view has no superview.
    @discardableResult
    func centerInSuperview(offset: CGPoint = .zero) -> [NSLayoutConstraint]? {
        guard let superview else { return nil }
        return layout.center(in: superview, offset: offset).activate()
    }
}
#endif
