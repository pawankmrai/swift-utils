//
//  PDFGenerator.swift
//  SwiftUtils
//
//  A chainable, auto-paginating PDF document builder on top of
//  UIGraphicsPDFRenderer. Compose plain text, attributed text, and images
//  into a multi-page PDF without hand-rolling Core Graphics/Core Text
//  page-flow logic.
//  Target: iOS 15+ / Swift 5.9+
//
//  Created by Pawan on 2026-07-28.
//

#if canImport(UIKit)
import UIKit
import CoreText

// MARK: - PDFPageSize

/// Standard and custom page size presets, expressed in points (1/72 inch).
public enum PDFPageSize: Sendable {
    /// 8.5 x 11 in (612 x 792 pt).
    case usLetter
    /// 210 x 297 mm (595 x 842 pt).
    case a4
    /// A custom page size, in points.
    case custom(width: CGFloat, height: CGFloat)

    var size: CGSize {
        switch self {
        case .usLetter: return CGSize(width: 612, height: 792)
        case .a4: return CGSize(width: 595, height: 842)
        case .custom(let width, let height): return CGSize(width: width, height: height)
        }
    }
}

// MARK: - PDFMetadata

/// Document metadata embedded into the generated PDF's info dictionary.
public struct PDFMetadata: Sendable {
    public var title: String?
    public var author: String?
    public var subject: String?
    public var creator: String

    /// Creates document metadata for a generated PDF.
    public init(title: String? = nil, author: String? = nil, subject: String? = nil, creator: String = "SwiftUtils") {
        self.title = title
        self.author = author
        self.subject = subject
        self.creator = creator
    }
}

// MARK: - PDFGeneratorError

/// Errors thrown while generating a PDF document.
public enum PDFGeneratorError: Error, Sendable, Equatable {
    /// `generate()` was called without any queued content.
    case emptyContent
}

// MARK: - PDFGenerator

/// A chainable builder that flows text, attributed text, and images across
/// automatically paginated PDF pages.
///
/// ```swift
/// let data = try PDFGenerator(metadata: .init(title: "Invoice #1042"))
///     .addText("Invoice #1042", font: .boldSystemFont(ofSize: 20))
///     .addSpacing(12)
///     .addText(receiptBody)
///     .addImage(logo, maxHeight: 80)
///     .generate()
///
/// try data.write(to: invoiceURL)
/// ```
public final class PDFGenerator {

    /// Page margins, in points.
    public struct Margins: Sendable {
        public var top: CGFloat
        public var left: CGFloat
        public var bottom: CGFloat
        public var right: CGFloat

        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        /// A 36pt (0.5") margin on all sides.
        public static let standard = Margins(top: 36, left: 36, bottom: 36, right: 36)
    }

    private enum Element {
        case attributedText(NSAttributedString)
        case image(UIImage, maxHeight: CGFloat?)
        case spacing(CGFloat)
        case pageBreak
    }

    private let pageSize: CGSize
    private let margins: Margins
    private let metadata: PDFMetadata
    private var elements: [Element] = []

    /// Creates a new PDF generator.
    /// - Parameters:
    ///   - pageSize: The page size preset. Defaults to `.usLetter`.
    ///   - margins: The page margins. Defaults to `.standard`.
    ///   - metadata: Metadata written into the PDF's info dictionary.
    public init(pageSize: PDFPageSize = .usLetter, margins: Margins = .standard, metadata: PDFMetadata = PDFMetadata()) {
        self.pageSize = pageSize.size
        self.margins = margins
        self.metadata = metadata
    }

    // MARK: - Content

    /// Queues a plain-text paragraph using the given font and color.
    @discardableResult
    public func addText(_ text: String, font: UIFont = .systemFont(ofSize: 12), color: UIColor = .black) -> Self {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        elements.append(.attributedText(attributed))
        return self
    }

    /// Queues a pre-styled attributed string, letting callers mix fonts,
    /// colors, and paragraph styles within a single block.
    @discardableResult
    public func addAttributedText(_ text: NSAttributedString) -> Self {
        elements.append(.attributedText(text))
        return self
    }

    /// Queues an image, scaled to fit the content width while preserving
    /// aspect ratio.
    /// - Parameter maxHeight: An optional cap on the rendered height, in points.
    @discardableResult
    public func addImage(_ image: UIImage, maxHeight: CGFloat? = nil) -> Self {
        elements.append(.image(image, maxHeight: maxHeight))
        return self
    }

    /// Queues vertical whitespace between elements.
    @discardableResult
    public func addSpacing(_ height: CGFloat) -> Self {
        elements.append(.spacing(height))
        return self
    }

    /// Forces the next queued element onto a fresh page.
    @discardableResult
    public func addPageBreak() -> Self {
        elements.append(.pageBreak)
        return self
    }

    /// Removes all queued content so the generator can be reused for a new document.
    public func reset() {
        elements.removeAll()
    }

    // MARK: - Rendering

    /// Renders all queued content into PDF document data, automatically
    /// flowing text and images across as many pages as needed.
    /// - Throws: `PDFGeneratorError.emptyContent` if nothing was queued.
    public func generate() throws -> Data {
        guard !elements.isEmpty else { throw PDFGeneratorError.emptyContent }

        let contentWidth = pageSize.width - margins.left - margins.right
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: makeFormat())

        return renderer.pdfData { context in
            var cursorY = margins.top
            context.beginPage()

            func startNewPage() {
                context.beginPage()
                cursorY = margins.top
            }

            for element in elements {
                switch element {
                case .pageBreak:
                    startNewPage()

                case .spacing(let height):
                    cursorY += height

                case .image(let image, let maxHeight):
                    guard image.size.width > 0, image.size.height > 0 else { continue }
                    let aspect = image.size.height / image.size.width
                    var drawWidth = contentWidth
                    var drawHeight = drawWidth * aspect
                    if let maxHeight, drawHeight > maxHeight {
                        drawHeight = maxHeight
                        drawWidth = drawHeight / aspect
                    }
                    if cursorY + drawHeight > pageSize.height - margins.bottom, cursorY > margins.top {
                        startNewPage()
                    }
                    let rect = CGRect(x: margins.left, y: cursorY, width: drawWidth, height: drawHeight)
                    image.draw(in: rect)
                    cursorY += drawHeight

                case .attributedText(let text):
                    var location = 0
                    let framesetter = CTFramesetterCreateWithAttributedString(text)

                    while location < text.length {
                        let availableHeight = pageSize.height - margins.bottom - cursorY
                        if availableHeight < 16 {
                            startNewPage()
                            continue
                        }

                        var fitRange = CFRange()
                        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                            framesetter,
                            CFRange(location: location, length: text.length - location),
                            nil,
                            CGSize(width: contentWidth, height: availableHeight),
                            &fitRange
                        )

                        if fitRange.length == 0 {
                            startNewPage()
                            continue
                        }

                        let drawHeight = min(ceil(suggested.height), availableHeight)
                        let rect = CGRect(x: margins.left, y: cursorY, width: contentWidth, height: drawHeight)
                        let path = CGPath(rect: rect, transform: nil)
                        let ctFrame = CTFramesetterCreateFrame(
                            framesetter,
                            CFRange(location: location, length: fitRange.length),
                            path,
                            nil
                        )

                        // CoreText draws bottom-up; UIGraphicsPDFRenderer's context
                        // follows UIKit's top-down convention, so flip locally.
                        let cg = context.cgContext
                        cg.saveGState()
                        cg.translateBy(x: 0, y: pageSize.height)
                        cg.scaleBy(x: 1, y: -1)
                        CTFrameDraw(ctFrame, cg)
                        cg.restoreGState()

                        cursorY += drawHeight
                        location += fitRange.length
                    }
                }
            }
        }
    }

    /// Renders and writes the generated PDF to disk.
    /// - Returns: The destination URL, for chaining.
    @discardableResult
    public func write(to url: URL) throws -> URL {
        let data = try generate()
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Private Helpers

    private func makeFormat() -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        var info: [String: Any] = [kCGPDFContextCreator as String: metadata.creator]
        if let title = metadata.title { info[kCGPDFContextTitle as String] = title }
        if let author = metadata.author { info[kCGPDFContextAuthor as String] = author }
        if let subject = metadata.subject { info[kCGPDFContextSubject as String] = subject }
        format.documentInfo = info
        return format
    }
}
#endif
