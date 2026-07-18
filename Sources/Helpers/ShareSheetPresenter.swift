//
//  ShareSheetPresenter.swift
//  SwiftUtils
//
//  A convenience wrapper around UIActivityViewController that removes the
//  usual boilerplate around iPad popover anchoring, activity exclusion,
//  and completion handling.
//

import UIKit

/// A single item to hand to the system share sheet.
///
/// `ShareItem` normalizes the handful of types `UIActivityViewController`
/// commonly shares — plain text, URLs, images, and files on disk — behind
/// one enum so callers don't need to remember which raw type each activity
/// expects.
public enum ShareItem {
    /// Plain text, such as a message or caption.
    case text(String)
    /// A web link or deep link.
    case url(URL)
    /// An image to share or save.
    case image(UIImage)
    /// A file on disk, shared by its file URL (e.g. a PDF or CSV export).
    case file(URL)

    /// The raw value `UIActivityViewController` expects for this item.
    fileprivate var activityItem: Any {
        switch self {
        case .text(let text): return text
        case .url(let url): return url
        case .image(let image): return image
        case .file(let url): return url
        }
    }
}

/// Presents the system share sheet (`UIActivityViewController`) with a
/// small, typed API for building share items, excluding activity types,
/// anchoring the iPad popover, and observing completion.
///
/// Usage:
/// ```swift
/// ShareSheetPresenter.present(
///     [.text("Check out this app!"), .url(appStoreURL)],
///     from: self,
///     sourceView: shareButton
/// ) { result in
///     if result.completed { print("Shared via \(result.activityType?.rawValue ?? "?")") }
/// }
/// ```
@MainActor
public enum ShareSheetPresenter {

    /// The outcome of a share sheet presentation.
    public struct Result {
        /// Whether the user completed a share/save action (`false` if they cancelled).
        public let completed: Bool
        /// The activity the user picked, if any (e.g. `.postToTwitter`, `.mail`, `.copyToPasteboard`).
        public let activityType: UIActivity.ActivityType?
        /// An error reported by the activity, if the action failed.
        public let error: Error?
    }

    /// Presents a share sheet with the given items.
    ///
    /// - Parameters:
    ///   - items: The content to share. Use ``ShareItem`` cases rather than raw
    ///     `Any` values so callers get compile-time checking of what's shareable.
    ///   - viewController: The presenting view controller.
    ///   - sourceView: On iPad, the view the popover arrow should point at.
    ///     Ignored on iPhone. If `nil` on iPad, the popover is anchored to the
    ///     presenting view's center, which is usually not what you want — pass
    ///     the tapped button or cell whenever possible.
    ///   - sourceRect: An optional rect within `sourceView` to anchor to
    ///     (defaults to the view's full bounds).
    ///   - excludedActivityTypes: Activities to hide from the sheet, e.g.
    ///     `[.assignToContact, .print]`.
    ///   - applicationActivities: Custom `UIActivity` subclasses to append,
    ///     such as an in-app "Save to Favorites" action.
    ///   - completion: Called after the sheet is dismissed with the outcome.
    ///     Not called if presentation itself is skipped (e.g. `items` is empty).
    public static func present(
        _ items: [ShareItem],
        from viewController: UIViewController,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        excludedActivityTypes: [UIActivity.ActivityType] = [],
        applicationActivities: [UIActivity]? = nil,
        completion: ((Result) -> Void)? = nil
    ) {
        guard !items.isEmpty else { return }

        let controller = UIActivityViewController(
            activityItems: items.map(\.activityItem),
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes

        controller.completionWithItemsHandler = { activityType, completed, _, error in
            completion?(Result(completed: completed, activityType: activityType, error: error))
        }

        if let popover = controller.popoverPresentationController {
            if let sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceRect ?? sourceView.bounds
            } else {
                // Fall back to anchoring on the presenting view so the
                // presentation doesn't crash on iPad when no anchor is given.
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(
                    x: viewController.view.bounds.midX,
                    y: viewController.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
        }

        viewController.present(controller, animated: true)
    }

    /// Presents a share sheet anchored to a `UIBarButtonItem`, such as a
    /// navigation bar share button.
    ///
    /// - Parameters:
    ///   - items: The content to share.
    ///   - viewController: The presenting view controller.
    ///   - barButtonItem: The bar button item to anchor the iPad popover to.
    ///   - excludedActivityTypes: Activities to hide from the sheet.
    ///   - applicationActivities: Custom activities to append.
    ///   - completion: Called after the sheet is dismissed with the outcome.
    public static func present(
        _ items: [ShareItem],
        from viewController: UIViewController,
        barButtonItem: UIBarButtonItem,
        excludedActivityTypes: [UIActivity.ActivityType] = [],
        applicationActivities: [UIActivity]? = nil,
        completion: ((Result) -> Void)? = nil
    ) {
        guard !items.isEmpty else { return }

        let controller = UIActivityViewController(
            activityItems: items.map(\.activityItem),
            applicationActivities: applicationActivities
        )
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            completion?(Result(completed: completed, activityType: activityType, error: error))
        }
        controller.popoverPresentationController?.barButtonItem = barButtonItem

        viewController.present(controller, animated: true)
    }

    /// Convenience for sharing a single piece of plain text.
    public static func presentText(
        _ text: String,
        from viewController: UIViewController,
        sourceView: UIView? = nil,
        completion: ((Result) -> Void)? = nil
    ) {
        present([.text(text)], from: viewController, sourceView: sourceView, completion: completion)
    }

    /// Convenience for sharing a single URL, e.g. a deep link or web page.
    public static func presentURL(
        _ url: URL,
        from viewController: UIViewController,
        sourceView: UIView? = nil,
        completion: ((Result) -> Void)? = nil
    ) {
        present([.url(url)], from: viewController, sourceView: sourceView, completion: completion)
    }

    /// Convenience for sharing or saving a single image.
    public static func presentImage(
        _ image: UIImage,
        from viewController: UIViewController,
        sourceView: UIView? = nil,
        completion: ((Result) -> Void)? = nil
    ) {
        present([.image(image)], from: viewController, sourceView: sourceView, completion: completion)
    }
}
