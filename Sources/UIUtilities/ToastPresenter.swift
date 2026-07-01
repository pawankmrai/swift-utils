//
//  ToastPresenter.swift
//  SwiftUtils
//
//  A lightweight, queue-based toast/banner presenter for UIKit.
//  Presents transient status messages with style presets, auto-dismiss,
//  tap-to-dismiss, and swipe-to-dismiss, serializing multiple toasts.
//  Target: iOS 15+ / Swift 5.9+
//

#if canImport(UIKit)
import UIKit

// MARK: - ToastStyle

/// Visual style for a toast, controlling its background, text color, and icon.
public enum ToastStyle: Sendable {
    case info
    case success
    case warning
    case error
    /// A fully custom style.
    case custom(background: UIColor, foreground: UIColor, icon: UIImage?)

    /// The toast's background color.
    public var backgroundColor: UIColor {
        switch self {
        case .info: return .systemBlue
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .error: return .systemRed
        case .custom(let background, _, _): return background
        }
    }

    /// The toast's text and icon tint color.
    public var foregroundColor: UIColor {
        switch self {
        case .custom(_, let foreground, _): return foreground
        default: return .white
        }
    }

    /// An optional SF Symbol icon shown before the message.
    public var icon: UIImage? {
        switch self {
        case .info: return UIImage(systemName: "info.circle.fill")
        case .success: return UIImage(systemName: "checkmark.circle.fill")
        case .warning: return UIImage(systemName: "exclamationmark.triangle.fill")
        case .error: return UIImage(systemName: "xmark.octagon.fill")
        case .custom(_, _, let icon): return icon
        }
    }
}

// MARK: - ToastPosition

/// Where a toast is anchored within its container view.
public enum ToastPosition: Sendable {
    case top
    case bottom
}

// MARK: - ToastConfiguration

/// Describes a single toast to be presented.
public struct ToastConfiguration: Sendable {
    public var message: String
    public var style: ToastStyle
    public var position: ToastPosition
    public var duration: TimeInterval
    public var isSwipeToDismissEnabled: Bool
    public var onTap: (@Sendable () -> Void)?

    /// Creates a toast configuration.
    /// - Parameters:
    ///   - message: The text to display.
    ///   - style: The visual style. Defaults to `.info`.
    ///   - position: Anchor position within the container. Defaults to `.bottom`.
    ///   - duration: Seconds before auto-dismiss. Defaults to `2.5`. Pass `0` to require manual dismissal.
    ///   - isSwipeToDismissEnabled: Whether a swipe gesture dismisses the toast. Defaults to `true`.
    ///   - onTap: Optional closure invoked when the toast is tapped; the toast dismisses immediately after.
    public init(
        message: String,
        style: ToastStyle = .info,
        position: ToastPosition = .bottom,
        duration: TimeInterval = 2.5,
        isSwipeToDismissEnabled: Bool = true,
        onTap: (@Sendable () -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.position = position
        self.duration = duration
        self.isSwipeToDismissEnabled = isSwipeToDismissEnabled
        self.onTap = onTap
    }
}

// MARK: - ToastPresenter

/// Presents queued, auto-dismissing toast banners over a container view.
///
/// ```swift
/// let presenter = ToastPresenter()
/// presenter.configure(container: view)
/// presenter.show("Saved successfully", style: .success)
/// presenter.show("Connection lost", style: .error, duration: 4)
/// ```
///
/// Toasts are shown one at a time, in the order they were queued. Call
/// `configure(container:)` once (e.g. in a root view controller or scene
/// delegate) before showing toasts.
@MainActor
public final class ToastPresenter {
    /// A shared, app-wide presenter instance for convenience.
    public static let shared = ToastPresenter()

    private weak var containerView: UIView?
    private var pendingToasts: [ToastConfiguration] = []
    private var isPresenting = false
    private var activeToastView: UIView?
    private var dismissWorkItem: DispatchWorkItem?
    private var tapHandlers: [ObjectIdentifier: (@Sendable () -> Void)] = [:]

    /// Creates a new, unconfigured toast presenter.
    public init() {}

    /// Sets the view that toasts will be presented over.
    /// - Parameter container: The container view (typically a window or root view).
    public func configure(container: UIView) {
        self.containerView = container
    }

    /// The number of toasts currently waiting to be shown (excludes the active one).
    public var queuedCount: Int { pendingToasts.count }

    /// Whether a toast is currently visible.
    public var isShowingToast: Bool { isPresenting }

    /// Queues a toast for presentation, showing it immediately if nothing else is active.
    /// - Parameter configuration: The toast to show.
    public func show(_ configuration: ToastConfiguration) {
        pendingToasts.append(configuration)
        presentNextIfNeeded()
    }

    /// Convenience overload to queue a simple text toast.
    /// - Returns: The configuration that was queued.
    @discardableResult
    public func show(
        _ message: String,
        style: ToastStyle = .info,
        position: ToastPosition = .bottom,
        duration: TimeInterval = 2.5
    ) -> ToastConfiguration {
        let configuration = ToastConfiguration(message: message, style: style, position: position, duration: duration)
        show(configuration)
        return configuration
    }

    /// Immediately dismisses the currently visible toast, if any, and advances the queue.
    public func dismissCurrent() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let toastView = activeToastView else { return }
        activeToastView = nil
        animateOut(toastView) { [weak self] in
            self?.isPresenting = false
            self?.presentNextIfNeeded()
        }
    }

    /// Removes all queued (not-yet-shown) toasts. Does not affect the currently visible toast.
    public func clearQueue() {
        pendingToasts.removeAll()
    }

    // MARK: - Presentation

    private func presentNextIfNeeded() {
        guard !isPresenting, !pendingToasts.isEmpty, let container = containerView else { return }
        let configuration = pendingToasts.removeFirst()
        isPresenting = true

        let toastView = makeToastView(for: configuration)
        container.addSubview(toastView)
        activeToastView = toastView
        layout(toastView, in: container, position: configuration.position)

        if configuration.isSwipeToDismissEnabled {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
            swipe.direction = configuration.position == .top ? .up : .down
            toastView.addGestureRecognizer(swipe)
        }

        animateIn(toastView)

        if configuration.duration > 0 {
            let workItem = DispatchWorkItem { [weak self] in self?.dismissCurrent() }
            dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + configuration.duration, execute: workItem)
        }
    }

    @objc private func handleSwipe() {
        dismissCurrent()
    }

    private func animateIn(_ view: UIView) {
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            view.alpha = 1
            view.transform = .identity
        }
    }

    private func animateOut(_ view: UIView, completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: 12)
        } completion: { _ in
            view.removeFromSuperview()
            completion()
        }
    }

    private func layout(_ toastView: UIView, in container: UIView, position: ToastPosition) {
        toastView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            toastView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            toastView.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        switch position {
        case .top:
            toastView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 12).isActive = true
        case .bottom:
            toastView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -12).isActive = true
        }
    }

    private func makeToastView(for configuration: ToastConfiguration) -> UIView {
        let card = UIView()
        card.backgroundColor = configuration.style.backgroundColor
        card.layer.cornerRadius = 12
        card.layer.masksToBounds = true

        let label = UILabel()
        label.text = configuration.message
        label.textColor = configuration.style.foregroundColor
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 2

        let stack: UIStackView
        if let icon = configuration.style.icon {
            let imageView = UIImageView(image: icon)
            imageView.tintColor = configuration.style.foregroundColor
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 20).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 20).isActive = true
            stack = UIStackView(arrangedSubviews: [imageView, label])
        } else {
            stack = UIStackView(arrangedSubviews: [label])
        }
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])

        if let onTap = configuration.onTap {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            card.addGestureRecognizer(tap)
            card.isUserInteractionEnabled = true
            tapHandlers[ObjectIdentifier(card)] = onTap
        }

        return card
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        let handler = tapHandlers.removeValue(forKey: ObjectIdentifier(view))
        handler?()
        dismissCurrent()
    }
}
#endif
