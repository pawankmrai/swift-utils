# QRCodeGenerator

Generates crisp QR code images from text, URLs, or raw `Data` using Core Image, so you don't have to hand-roll `CIFilter` plumbing or fight the blurry default output when scaling up. Includes configurable error-correction levels, optional foreground/background recoloring on UIKit platforms, and a `WIFI:` payload builder for shareable network-join codes.

## API

| Type / Method / Property | Description |
|---|---|
| `QRCodeCorrectionLevel` | `.low` (~7%), `.medium` (~15%), `.quartile` (~25%), `.high` (~30%) recoverable codewords |
| `QRCodeGeneratorError` | `.emptyPayload`, `.filterUnavailable`, `.renderingFailed` |
| `QRCodeGenerator.generate(from:correctionLevel:scale:)` | Generates a `CGImage` from `Data`, throws on empty payload or render failure |
| `QRCodeGenerator.generate(from:correctionLevel:scale:)` | Overload accepting a `String`, encoded as UTF-8 |
| `QRCodeGenerator.generateImage(from:correctionLevel:scale:foregroundColor:backgroundColor:)` | UIKit only — returns a `UIImage`, optionally recolored |
| `QRCodeGenerator.wifiPayload(ssid:password:security:isHidden:)` | Builds a standard `WIFI:T:...;S:...;P:...;H:...;;` payload string with field escaping |

## Examples

### Generating a basic QR code

```swift
import SwiftUtilsHelpers
import UIKit

let cgImage = try QRCodeGenerator.generate(from: "https://swift.org", scale: 12)
imageView.image = UIImage(cgImage: cgImage)
```

### UIKit convenience with custom colors

```swift
let image = try QRCodeGenerator.generateImage(
    from: "https://example.com/invite/abc123",
    correctionLevel: .high,
    scale: 12,
    foregroundColor: .systemIndigo,
    backgroundColor: .white
)
inviteImageView.image = image
```

### SwiftUI

```swift
import SwiftUI
import SwiftUtilsHelpers

struct QRCodeView: View {
    let payload: String
    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).interpolation(.none).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task {
            uiImage = try? QRCodeGenerator.generateImage(from: payload, scale: 12)
        }
    }
}
```

### Encoding raw `Data` (e.g. a signed token)

```swift
let tokenData = try JSONEncoder().encode(signedToken)
let cgImage = try QRCodeGenerator.generate(from: tokenData, correctionLevel: .quartile, scale: 10)
```

### Building a Wi-Fi join code

Scanning the resulting code offers to join the network directly — no typing required.

```swift
let payload = QRCodeGenerator.wifiPayload(
    ssid: "Office Guest",
    password: "welcome2024",
    security: "WPA",
    isHidden: false
)
let wifiCode = try QRCodeGenerator.generateImage(from: payload, correctionLevel: .high, scale: 12)
```

### Choosing a correction level for a logo overlay

Use `.high` when a logo or icon will occlude the center of the code, since it tolerates the most damage:

```swift
let baseImage = try QRCodeGenerator.generateImage(
    from: "https://myapp.com/share/xyz",
    correctionLevel: .high,
    scale: 15
)
// Composite a small logo over `baseImage` in the center — .high correction keeps it scannable.
```

### Handling errors

```swift
do {
    let image = try QRCodeGenerator.generate(from: userInput, scale: 10)
    display(image)
} catch QRCodeGeneratorError.emptyPayload {
    showAlert("Enter some text to generate a code.")
} catch {
    showAlert("Couldn't generate QR code: \(error)")
}
```
