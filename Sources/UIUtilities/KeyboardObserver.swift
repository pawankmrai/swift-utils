//
//  KeyboardObserver.swift
//  SwiftUtils
//
//  Observes system keyboard show/hide/frame-change notifications and publishes
//  keyboard height, visibility, and animation timing so UIKit and SwiftUI
//  screens can react without wiring up NotificationCenter boilerplate by hand.
//  Target: iOS 15+ / Swift 5.9+
//

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
import UIKit
import Combine

// MARK: - KeyboardObserver

/// Tracks the on-screen keyboard's height, visibility, and animation timing.
///
/// `KeyboardObserver` listens to `UIResponder` keyboard notifications and republishes
/// them as `@Published` properties, matching the system's own animation curve and
/// duration so consumers can animate in lockstep with the keyboard.
///
/// Use the shared instance for app-wide observation, or create your own for
/// scoped/testable usage:
///
/// ```swift
/// let observer = KeyboardObserver()
/// observer.$keyboardHeight.sink { height in ... }
/// ```
@MainActor
public final class KeyboardObserver: ObservableObject {

    /// A shared, app-wide observer. Most consumers can use this instead of creating their own.
    public static let shared = KeyboardObserver()

    /// Current height of the keyboard intruding into the view, in points. `0` when hidden.
    @Published public private(set) var keyboardHeight: CGFloat = 0

    /// Whether the keyboard is currently visible.
    @Published public private(set) var isVisible: Bool = false

    /// Duration of the keyboard's current show/hide animation, taken from the system notification.
    @Published public private(set) var animationDuration: TimeInterval = 0.25

    /// Raw `UIView.AnimationOptions` curve for the keyboard's current animation,
    /// suitable for passing directly to `UIView.animate(withDuration:delay:options:animations:)`.
    @Published public private(set) var animationOptions: UIView.AnimationOptions = [.curveEaseInOut]

    private var cancellables = Set<AnyCancellable>()

    /// Creates a new observer and immediately begins listening for keyboard notifications.
    public init() {
        observe()
    }

    /// An async stream of keyboard height updates, for use in Swift concurrency contexts.
    public var heightStream: AsyncStream<CGFloat> {
        AsyncStream { continuation in
            let cancellable = $keyboardHeight
                .sink { continuation.yield($0) }
            continuation.onTermination = { _ in
                Task { @MainActor in cancellable.cancel() }
            }
        }
    }

    private func observe() {
        let center = NotificationCenter.default

        Publishers.Merge(
            center.publisher(for: UIResponder.keyboardWillShowNotification),
            center.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        )
        .sink { [weak self] in self?.handle($0, visible: true) }
        .store(in: &cancellables)

        center.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] in self?.handle($0, visible: false) }
            .store(in: &cancellables)
    }

    private func handle(_ notification: Notification, visible: Bool) {
        guard let userInfo = notification.userInfo else { return }

        let frame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7

        let screenHeight = UIScreen.main.bounds.height
        let height = visible ? max(0, screenHeight - frame.minY) : 0

        animationDuration = duration
        animationOptions = UIView.AnimationOptions(rawValue: curveRaw << 16)
        keyboardHeight = height
        isVisible = visible && height > 0
    }
}

// MARK: - UIScrollView + KeyboardObserver

extension UIScrollView {

    /// Automatically adjusts the scroll view's bottom content inset (and scroll
    /// indicator inset) to avoid the keyboard, animating in step with the
    /// keyboard's own show/hide transition.
    ///
    /// - Parameter observer: The observer to follow. Defaults to `.shared`.
    /// - Returns: A `Cancellable` the caller must retain for as long as the
    ///   adjustment should remain active.
    @MainActor
    public func swiftUtils_avoidKeyboard(using observer: KeyboardObserver = .shared) -> AnyCancellable {
        let originalBottomInset = contentInset.bottom
        return observer.$keyboardHeight
            .removeDuplicates()
            .sink { [weak self] height in
                guard let self else { return }
                let bottomInset = height > 0
                    ? max(originalBottomInset, height - self.safeAreaInsets.bottom + originalBottomInset)
                    : originalBottomInset
                UIView.animate(withDuration: observer.animationDuration, delay: 0, options: observer.animationOptions) {
                    self.contentInset.bottom = bottomInset
                    self.verticalScrollIndicatorInsets.bottom = bottomInset
                }
            }
    }
}

#if canImport(SwiftUI)
import SwiftUI

// MARK: - View + keyboardAdaptive

@available(iOS 15.0, *)
private struct KeyboardAdaptive: ViewModifier {
    @ObservedObject var observer: KeyboardObserver
    let extraPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.bottom, observer.isVisible ? observer.keyboardHeight + extraPadding : 0)
            .animation(.easeOut(duration: observer.animationDuration), value: observer.keyboardHeight)
    }
}

@available(iOS 15.0, *)
extension View {

    /// Pads the bottom of the view to keep its content clear of the on-screen
    /// keyboard, animating alongside the keyboard's own show/hide transition.
    ///
    /// - Parameters:
    ///   - extraPadding: Additional space to add on top of the keyboard height. Defaults to `0`.
    ///   - observer: The observer to follow. Defaults to `.shared`.
    public func keyboardAdaptive(extraPadding: CGFloat = 0, observer: KeyboardObserver = .shared) -> some View {
        modifier(KeyboardAdaptive(observer: observer, extraPadding: extraPadding))
    }
}
#endif

#endif
