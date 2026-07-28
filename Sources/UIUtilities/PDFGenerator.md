# PDFGenerator

A chainable, auto-paginating PDF document builder on top of `UIGraphicsPDFRenderer`. Compose plain text, pre-styled attributed text, and images into a multi-page PDF without hand-rolling Core Graphics/Core Text page-flow logic — `PDFGenerator` measures each block with Core Text and automatically starts new pages when content overflows.

## API

| Type / Method | Description |
|---|---|
| `PDFGenerator(pageSize:margins:metadata:)` | Create a new generator with a page size preset, margins, and document metadata |
| `addText(_:font:color:)` | Queue a plain-text paragraph with word wrapping |
| `addAttributedText(_:)` | Queue a pre-styled `NSAttributedString` |
| `addImage(_:maxHeight:)` | Queue an image, scaled to content width and optionally capped by height |
| `addSpacing(_:)` | Queue vertical whitespace between elements |
| `addPageBreak()` | Force the next queued element onto a fresh page |
| `reset()` | Clear all queued content so the generator can be reused |
| `generate()` | Render all queued content into PDF `Data`, throwing if nothing was queued |
| `write(to:)` | Render and write the PDF directly to a file URL |

All `add*` methods return `Self`, so calls can be chained fluently.

### PDFPageSize

| Case | Description |
|---|---|
| `.usLetter` | 8.5 x 11 in (612 x 792 pt) — the default |
| `.a4` | 210 x 297 mm (595 x 842 pt) |
| `.custom(width:height:)` | Any page size, in points |

### PDFGenerator.Margins

| Member | Description |
|---|---|
| `top`, `left`, `bottom`, `right` | Margin values, in points |
| `.standard` | 36pt (0.5") on all sides |

### PDFMetadata

| Property | Description |
|---|---|
| `title` | Document title (optional) |
| `author` | Document author (optional) |
| `subject` | Document subject (optional) |
| `creator` | Creator string embedded in the PDF; defaults to `"SwiftUtils"` |

### PDFGeneratorError

| Case | Description |
|---|---|
| `.emptyContent` | Thrown by `generate()` when no content was queued |

## Examples

```swift
import SwiftUtilsUIUtilities

// Basic single-page document
let data = try PDFGenerator()
    .addText("Hello, PDF!")
    .generate()

try data.write(to: outputURL)
```

```swift
// A multi-section invoice with mixed content and metadata
let logo = UIImage(named: "CompanyLogo")!

let generator = PDFGenerator(
    pageSize: .usLetter,
    margins: .standard,
    metadata: PDFMetadata(title: "Invoice #1042", author: "Acme Inc.", subject: "Customer Invoice")
)

try generator
    .addImage(logo, maxHeight: 60)
    .addSpacing(16)
    .addText("Invoice #1042", font: .boldSystemFont(ofSize: 22))
    .addText("Issued: July 28, 2026", font: .systemFont(ofSize: 12), color: .darkGray)
    .addSpacing(20)
    .addText(lineItemsSummary)
    .addPageBreak()
    .addText("Terms & Conditions", font: .boldSystemFont(ofSize: 16))
    .addText(termsText)
    .write(to: invoiceURL)
```

```swift
// Mixing plain and pre-styled attributed text
let highlighted = NSMutableAttributedString(
    string: "Amount Due: $482.00",
    attributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.systemRed]
)

let data = try PDFGenerator()
    .addText("Summary", font: .boldSystemFont(ofSize: 20))
    .addAttributedText(highlighted)
    .generate()
```

```swift
// Long text automatically flows across as many pages as needed
let report = PDFGenerator()
    .addText("Quarterly Report", font: .boldSystemFont(ofSize: 24))
    .addSpacing(12)
    .addText(veryLongReportBody) // spans multiple pages automatically

let reportData = try report.generate()
```

```swift
// Reusing a generator for a batch of similar documents
let generator = PDFGenerator(metadata: PDFMetadata(creator: "ReceiptPrinter"))

for order in orders {
    generator.reset()
    generator
        .addText("Receipt for Order #\(order.id)", font: .boldSystemFont(ofSize: 18))
        .addText(order.summary)

    let receiptData = try generator.generate()
    try receiptData.write(to: receiptsFolder.appendingPathComponent("\(order.id).pdf"))
}
```

```swift
// Handling the empty-content error
let empty = PDFGenerator()
do {
    _ = try empty.generate()
} catch PDFGeneratorError.emptyContent {
    print("Nothing to render yet — queue some content first.")
}
```
