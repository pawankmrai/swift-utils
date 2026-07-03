//
//  PasteboardManager.swift
//  SwiftUtils
//
//  A type-safe, testable wrapper around UIPasteboard with support for
//  expiring items, local-only (non-cloud-synced) copies, and change
//  observation.
//

import UIKit

/// A type-safe wrapper around `UIPasteboard` that adds expiring items,
/// local-only copies, and a closure-based change observer.
///
/// `PasteboardManager` normalizes the string-keyed, `Any`-typed nature of
/// `UIPasteboard` into small, typed methods for the content types apps
/// actually copy and paste: strings, URLs, images, and colors.
///
/// Usage:
/// ```swift
/// PasteboardManager.shared.copy("promo-code-123", expiresIn: 60)
/// let code = PasteboardManager.shared.string()
/// ```
public final class PasteboardManager: @unchecked Sendable {

    // MARK: - Types

    /// Uniform Type Identifiers used for the content this manager reads and writes.
    private enum UTI {
        static let plainText = "public.utf8-plain-text"
        static let url = "public.url"
        static let png = "public.png"
        static let color = "com.swiftutils.pasteboard-color"
    }

    // MARK: - Singleton

    /// Shared manager backed by the system's general pasteboard.
    public static let shared = PasteboardManager()

    // MARK: - Properties

    private let pasteboard: UIPasteboard
    private var changeObserver: NSObjectProtocol?
    private var changeHandlers: [UUID: () -> Void] = [:]
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a manager around the general (system-wide) pasteboard.
    public init() {
        self.pasteboard = .general
    }

    /// Creates a manager around a named, app-specific pasteboard.
    ///
    /// - Parameters:
    ///   - name: The pasteboard name.
    ///   - create: Whether to create the pasteboard if it doesn't already exist.
    public init(named name: UIPasteboard.Name, create: Bool = true) {
        self.pasteboard = UIPasteboard(name: name, create: create) ?? .general
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    // MARK: - Copying

    /// Copies a string to the pasteboard.
    ///
    /// - Parameters:
    ///   - string: The text to copy.
    ///   - expiresIn: Optional lifetime in seconds after which the system clears the item.
    ///   - localOnly: When `true`, the item is excluded from Universal Clipboard / Handoff sync.
    public func copy(_ string: String, expiresIn: TimeInterval? = nil, localOnly: Bool = false) {
        setItem([UTI.plainText: string], expiresIn: expiresIn, localOnly: localOnly)
    }

    /// Copies a URL to the pasteboard.
    public func copy(_ url: URL, expiresIn: TimeInterval? = nil, localOnly: Bool = false) {
        setItem([UTI.url: url, UTI.plainText: url.absoluteString], expiresIn: expiresIn, localOnly: localOnly)
    }

    /// Copies an image to the pasteboard as PNG data.
    public func copy(_ image: UIImage, expiresIn: TimeInterval? = nil, localOnly: Bool = false) {
        guard let data = image.pngData() else { return }
        setItem([UTI.png: data], expiresIn: expiresIn, localOnly: localOnly)
    }

    /// Copies a color to the pasteboard as securely-archived `UIColor` data.
    public func copy(_ color: UIColor, expiresIn: TimeInterval? = nil, localOnly: Bool = false) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else { return }
        setItem([UTI.color: data], expiresIn: expiresIn, localOnly: localOnly)
    }

    // MARK: - Pasting

    /// The current string on the pasteboard, if any.
    public func string() -> String? {
        pasteboard.string
    }

    /// The current URL on the pasteboard, if any.
    ///
    /// Falls back to parsing the pasteboard string as a URL when no
    /// dedicated URL item is present.
    public func url() -> URL? {
        if let url = pasteboard.url {
            return url
        }
        guard let string = pasteboard.string else { return nil }
        return URL(string: string)
    }

    /// The current image on the pasteboard, if any.
    public func image() -> UIImage? {
        pasteboard.image
    }

    /// The current color on the pasteboard, if any, unarchived from a prior `copy(_:)` call.
    public func color() -> UIColor? {
        guard let data = pasteboard.data(forPasteboardType: UTI.color) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
    }

    // MARK: - Inspection

    /// Whether the pasteboard currently holds plain text.
    public var hasStrings: Bool { pasteboard.hasStrings }

    /// Whether the pasteboard currently holds a URL.
    public var hasURLs: Bool { pasteboard.hasURLs }

    /// Whether the pasteboard currently holds an image.
    public var hasImages: Bool { pasteboard.hasImages }

    /// The number of items currently on the pasteboard.
    public var itemCount: Int { pasteboard.numberOfItems }

    /// Removes all items from the pasteboard.
    public func clear() {
        pasteboard.items = []
    }

    // MARK: - Change Observation

    /// Registers a handler that's called whenever the pasteboard's contents change.
    ///
    /// - Parameter handler: Invoked on the main queue when the pasteboard changes.
    /// - Returns: A token; pass it to `removeChangeHandler(_:)` to stop observing.
    @discardableResult
    public func onChange(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        changeHandlers[token] = handler
        let shouldSubscribe = changeObserver == nil
        lock.unlock()

        if shouldSubscribe {
            let observer = NotificationCenter.default.addObserver(
                forName: UIPasteboard.changedNotification,
                object: pasteboard,
                queue: .main
            ) { [weak self] _ in
                self?.notifyChangeHandlers()
            }
            lock.lock()
            changeObserver = observer
            lock.unlock()
        }
        return token
    }

    /// Removes a previously registered change handler.
    public func removeChangeHandler(_ token: UUID) {
        lock.lock()
        changeHandlers.removeValue(forKey: token)
        lock.unlock()
    }

    private func notifyChangeHandlers() {
        lock.lock()
        let handlers = Array(changeHandlers.values)
        lock.unlock()
        handlers.forEach { $0() }
    }

    // MARK: - Private Helpers

    private func setItem(_ representations: [String: Any], expiresIn: TimeInterval?, localOnly: Bool) {
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if let expiresIn {
            options[.expirationDate] = Date().addingTimeInterval(expiresIn)
        }
        if localOnly {
            options[.localOnly] = true
        }
        pasteboard.setItems([representations], options: options)
    }
}
