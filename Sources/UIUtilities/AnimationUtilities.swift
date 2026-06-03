import UIKit

// MARK: - AnimationConfig

/// A declarative, chainable configuration for UIView animations.
///
/// Build complex animation sequences with a fluent API:
/// ```swift
/// AnimationConfig()
///     .duration(0.35)
///     .springDamping(0.7)
///     .curve(.easeOut)
///     .animate { view.alpha = 1 }
/// ```
public struct AnimationConfig {

    // MARK: - Properties

    private var animDuration: TimeInterval = 0.3
    private var animDelay: TimeInterval = 0
    private var animDamping: CGFloat = 1.0
    private var animVelocity: CGFloat = 0
    private var animOptions: UIView.AnimationOptions = []
    private var animCurve: UIView.AnimationCurve?

    // MARK: - Init

    public init() {}

    // MARK: - Chainable Setters

    /// Set the animation duration in seconds.
    public func duration(_ value: TimeInterval) -> AnimationConfig {
        var copy = self
        copy.animDuration = value
        return copy
    }

    /// Set the delay before the animation starts.
    public func delay(_ value: TimeInterval) -> AnimationConfig {
        var copy = self
        copy.animDelay = value
        return copy
    }

    /// Set the spring damping ratio (0…1). Values < 1 produce a bounce.
    public func springDamping(_ value: CGFloat) -> AnimationConfig {
        var copy = self
        copy.animDamping = value
        return copy
    }

    /// Set the initial spring velocity.
    public func initialVelocity(_ value: CGFloat) -> AnimationConfig {
        var copy = self
        copy.animVelocity = value
        return copy
    }

    /// Set UIView animation options (e.g., `.allowUserInteraction`).
    public func options(_ value: UIView.AnimationOptions) -> AnimationConfig {
        var copy = self
        copy.animOptions = value
        return copy
    }

    /// Set a timing curve. Overrides `options` curve flags.
    public func curve(_ value: UIView.AnimationCurve) -> AnimationConfig {
        var copy = self
        copy.animCurve = value
        return copy
    }

    // MARK: - Execute

    /// Run the animation with the current configuration.
    @discardableResult
    public func animate(
        _ animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) -> AnimationConfig {
        var opts = animOptions
        if let curve = animCurve {
            opts.insert(curveOption(for: curve))
        }
        UIView.animate(
            withDuration: animDuration,
            delay: animDelay,
            usingSpringWithDamping: animDamping,
            initialSpringVelocity: animVelocity,
            options: opts,
            animations: animations,
            completion: completion
        )
        return self
    }

    /// Run the animation and return its completion via async/await.
    @discardableResult
    public func animate(_ animations: @escaping () -> Void) async -> Bool {
        var opts = animOptions
        if let curve = animCurve {
            opts.insert(curveOption(for: curve))
        }
        return await withCheckedContinuation { continuation in
            UIView.animate(
                withDuration: animDuration,
                delay: animDelay,
                usingSpringWithDamping: animDamping,
                initialSpringVelocity: animVelocity,
                options: opts,
                animations: animations
            ) { finished in
                continuation.resume(returning: finished)
            }
        }
    }

    private func curveOption(for curve: UIView.AnimationCurve) -> UIView.AnimationOptions {
        switch curve {
        case .easeInOut: return .curveEaseInOut
        case .easeIn:    return .curveEaseIn
        case .easeOut:   return .curveEaseOut
        case .linear:    return .curveLinear
        @unknown default: return .curveEaseInOut
        }
    }
}

// MARK: - Presets

extension AnimationConfig {

    /// A quick fade with 0.2s duration.
    public static var quickFade: AnimationConfig {
        AnimationConfig().duration(0.2).curve(.easeOut)
    }

    /// A standard spring with slight bounce.
    public static var spring: AnimationConfig {
        AnimationConfig().duration(0.5).springDamping(0.7).initialVelocity(0.3)
    }

    /// A bouncy spring suitable for pop-in effects.
    public static var bouncy: AnimationConfig {
        AnimationConfig().duration(0.6).springDamping(0.5).initialVelocity(0.8)
    }

    /// A slow ease-in-out for layout changes.
    public static var smooth: AnimationConfig {
        AnimationConfig().duration(0.35).curve(.easeInOut)
    }
}

// MARK: - UIView Convenience Extensions

extension UIView {

    /// Fade the view in.
    public func fadeIn(
        duration: TimeInterval = 0.3,
        delay: TimeInterval = 0,
        completion: ((Bool) -> Void)? = nil
    ) {
        alpha = 0
        AnimationConfig()
            .duration(duration)
            .delay(delay)
            .curve(.easeOut)
            .animate({ self.alpha = 1 }, completion: completion)
    }

    /// Fade the view out.
    public func fadeOut(
        duration: TimeInterval = 0.3,
        delay: TimeInterval = 0,
        completion: ((Bool) -> Void)? = nil
    ) {
        AnimationConfig()
            .duration(duration)
            .delay(delay)
            .curve(.easeOut)
            .animate({ self.alpha = 0 }, completion: completion)
    }

    /// Scale the view with a spring effect (e.g., for button taps).
    public func popScale(
        to scale: CGFloat = 1.1,
        duration: TimeInterval = 0.15,
        completion: ((Bool) -> Void)? = nil
    ) {
        AnimationConfig()
            .duration(duration)
            .springDamping(0.5)
            .animate({ self.transform = CGAffineTransform(scaleX: scale, y: scale) }) { _ in
                AnimationConfig()
                    .duration(duration)
                    .springDamping(0.5)
                    .animate({ self.transform = .identity }, completion: completion)
            }
    }

    /// Shake the view horizontally (e.g., for input validation errors).
    public func shake(
        intensity: CGFloat = 10,
        duration: TimeInterval = 0.5
    ) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = duration
        animation.values = [
            0, -intensity, intensity, -intensity * 0.8,
            intensity * 0.8, -intensity * 0.4, intensity * 0.4, 0
        ]
        layer.add(animation, forKey: "shake")
    }

    /// Slide the view in from an edge.
    public func slideIn(
        from edge: SlideEdge,
        offset: CGFloat = 100,
        duration: TimeInterval = 0.4,
        completion: ((Bool) -> Void)? = nil
    ) {
        let (dx, dy) = edge.translationComponents(offset: offset)
        transform = CGAffineTransform(translationX: dx, y: dy)
        alpha = 0
        AnimationConfig.spring
            .duration(duration)
            .animate({
                self.transform = .identity
                self.alpha = 1
            }, completion: completion)
    }
}

// MARK: - SlideEdge

/// Edge from which a slide animation originates.
public enum SlideEdge {
    case top, bottom, leading, trailing

    func translationComponents(offset: CGFloat) -> (CGFloat, CGFloat) {
        switch self {
        case .top:      return (0, -offset)
        case .bottom:   return (0, offset)
        case .leading:  return (-offset, 0)
        case .trailing: return (offset, 0)
        }
    }
}

// MARK: - AnimationSequence

/// Run a chain of animations sequentially.
///
/// ```swift
/// AnimationSequence()
///     .step(duration: 0.3) { view.alpha = 1 }
///     .step(duration: 0.2) { view.transform = .identity }
///     .run()
/// ```
public final class AnimationSequence {

    private var steps: [(config: AnimationConfig, animations: () -> Void)] = []

    public init() {}

    /// Add a step to the sequence.
    @discardableResult
    public func step(
        config: AnimationConfig = AnimationConfig(),
        _ animations: @escaping () -> Void
    ) -> AnimationSequence {
        steps.append((config, animations))
        return self
    }

    /// Convenience: add a step with just a duration.
    @discardableResult
    public func step(
        duration: TimeInterval,
        _ animations: @escaping () -> Void
    ) -> AnimationSequence {
        steps.append((AnimationConfig().duration(duration), animations))
        return self
    }

    /// Execute all steps in order.
    public func run(completion: (() -> Void)? = nil) {
        guard !steps.isEmpty else {
            completion?()
            return
        }
        runStep(at: 0, completion: completion)
    }

    /// Execute all steps in order using async/await.
    public func run() async {
        for (config, animations) in steps {
            _ = await config.animate(animations)
        }
    }

    private func runStep(at index: Int, completion: (() -> Void)?) {
        guard index < steps.count else {
            completion?()
            return
        }
        let (config, animations) = steps[index]
        config.animate(animations) { [weak self] _ in
            self?.runStep(at: index + 1, completion: completion)
        }
    }
}
