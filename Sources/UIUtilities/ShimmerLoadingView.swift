//
//  ShimmerLoadingView.swift
//  SwiftUtils
//
//  Skeleton / shimmer placeholder views for loading states, with both
//  a UIKit `UIView` subclass and a SwiftUI `ViewModifier`.
//  Target: iOS 15+ / Swift 5.9+
//

#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(UIKit)

// MARK: - ShimmerDirection

/// The direction the shimmer highlight travels across a view.
public enum ShimmerDirection: Equatable {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
}

// MARK: - ShimmerConfiguration

/// Visual configuration for a shimmer animation.
public struct ShimmerConfiguration {
    /// Base (resting) color of the skeleton.
    public var baseColor: UIColor
    /// Highlight color that sweeps across the base color.
    public var highlightColor: UIColor
    /// Duration of one shimmer pass, in seconds.
    public var duration: TimeInterval
    /// Delay between consecutive shimmer passes, in seconds.
    public var pauseBetweenPasses: TimeInterval
    /// Direction of the shimmer sweep.
    public var direction: ShimmerDirection
    /// Fractional width of the highlight band (0...1) relative to the view.
    public var bandWidth: CGFloat

    public init(
        baseColor: UIColor = UIColor.systemGray5,
        highlightColor: UIColor = UIColor.systemGray6,
        duration: TimeInterval = 1.2,
        pauseBetweenPasses: TimeInterval = 0.3,
        direction: ShimmerDirection = .leftToRight,
        bandWidth: CGFloat = 0.3
    ) {
        self.baseColor = baseColor
        self.highlightColor = highlightColor
        self.duration = duration
        self.pauseBetweenPasses = pauseBetweenPasses
        self.direction = direction
        self.bandWidth = bandWidth
    }

    /// A subtle, dark-mode-friendly default configuration.
    public static let `default` = ShimmerConfiguration()
}

// MARK: - ShimmerLoadingView

/// A `UIView` that renders an animated shimmer placeholder, suitable for
/// skeleton-screen loading states (e.g. list rows, avatars, text lines).
///
/// ```swift
/// let avatar = ShimmerLoadingView()
/// avatar.layer.cornerRadius = 24
/// avatar.startShimmering()
/// ```
///
/// Call `stopShimmering()` (or `isShimmering = false`) once real content
/// is ready, typically alongside a cross-fade into the loaded view.
public final class ShimmerLoadingView: UIView {

    // MARK: - Properties

    /// The current shimmer configuration. Changing this while shimmering
    /// restarts the animation with the new settings.
    public var configuration: ShimmerConfiguration {
        didSet { if isShimmering { restart() } }
    }

    /// Whether the shimmer animation is currently running.
    public private(set) var isShimmering = false

    private let gradientLayer = CAGradientLayer()

    // MARK: - Init

    public init(configuration: ShimmerConfiguration = .default) {
        self.configuration = configuration
        super.init(frame: .zero)
        setUp()
    }

    public required init?(coder: NSCoder) {
        self.configuration = .default
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = configuration.baseColor
        clipsToBounds = true

        gradientLayer.colors = [
            configuration.baseColor.cgColor,
            configuration.highlightColor.cgColor,
            configuration.baseColor.cgColor,
        ]
        gradientLayer.locations = [0, 0.5, 1]
        applyDirection()
        layer.addSublayer(gradientLayer)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds.insetBy(
            dx: -bounds.width * 0.5,
            dy: -bounds.height * 0.5
        )
    }

    private func applyDirection() {
        switch configuration.direction {
        case .leftToRight:
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        case .rightToLeft:
            gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
        case .topToBottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        case .bottomToTop:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        }
    }

    // MARK: - Control

    /// Starts (or restarts) the shimmer animation.
    public func startShimmering() {
        backgroundColor = configuration.baseColor
        gradientLayer.colors = [
            configuration.baseColor.cgColor,
            configuration.highlightColor.cgColor,
            configuration.baseColor.cgColor,
        ]
        applyDirection()

        let fromValue: [NSNumber]
        let toValue: [NSNumber]
        let half = Double(configuration.bandWidth) / 2

        switch configuration.direction {
        case .leftToRight, .topToBottom:
            fromValue = [-1, -1 + half, -1 + half * 2] as [NSNumber]
            toValue = [1 - half * 2, 1 - half, 1] as [NSNumber]
        case .rightToLeft, .bottomToTop:
            fromValue = [1 - half * 2, 1 - half, 1] as [NSNumber]
            toValue = [-1, -1 + half, -1 + half * 2] as [NSNumber]
        }

        let animation = CAKeyframeAnimation(keyPath: "locations")
        animation.values = [fromValue, toValue]
        animation.keyTimes = [0, 1]
        animation.duration = configuration.duration
        animation.beginTime = 0
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        let group = CAAnimationGroup()
        group.animations = [animation]
        group.duration = configuration.duration + configuration.pauseBetweenPasses
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false

        gradientLayer.add(group, forKey: "shimmer")
        isShimmering = true
    }

    /// Stops the shimmer animation, leaving the base color visible.
    public func stopShimmering() {
        gradientLayer.removeAnimation(forKey: "shimmer")
        isShimmering = false
    }

    private func restart() {
        stopShimmering()
        startShimmering()
    }
}

#endif

#if canImport(SwiftUI)

// MARK: - SwiftUI Shimmer Modifier

@available(iOS 15.0, *)
private struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    let duration: Double

    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .redacted(reason: isActive ? .placeholder : [])
            .overlay {
                if isActive {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.5), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 1.5)
                        .offset(x: phase * proxy.size.width)
                        .blendMode(.screen)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard isActive else { return }
                withAnimation(
                    .linear(duration: duration).repeatForever(autoreverses: false)
                ) {
                    phase = 1.6
                }
            }
    }
}

@available(iOS 15.0, *)
public extension View {
    /// Applies a redacted skeleton appearance with an animated shimmer sweep.
    ///
    /// ```swift
    /// Text(user.name)
    ///     .shimmering(isActive: viewModel.isLoading)
    /// ```
    ///
    /// - Parameters:
    ///   - isActive: Whether the shimmer/redaction should be shown.
    ///   - duration: Duration of one shimmer sweep, in seconds. Default `1.2`.
    func shimmering(isActive: Bool, duration: Double = 1.2) -> some View {
        modifier(ShimmerModifier(isActive: isActive, duration: duration))
    }
}

#endif
