# CertificatePinner

SSL/TLS certificate pinning for `URLSession`, validated against SHA-256 digests of DER-encoded certificates. Protects against man-in-the-middle attacks from rogue or compromised CAs by requiring the server's certificate chain to include a certificate you've explicitly trusted, in addition to standard system trust evaluation.

The validation core (`CertificatePinner.validate(host:chain:)`) is pure and works on plain `Data`, so it's fully unit testable without real certificates or a network connection. `PinningURLSessionDelegate` wires that core up to `URLSession` via `SecTrust`.

## API

| Type | Description |
|---|---|
| `CertificatePin` | A pinned certificate, identified by the SHA-256 digest of its DER bytes |
| `CertificatePin.init(certificateData:)` | Builds a pin by hashing raw DER certificate data |
| `CertificatePin.init?(sha256Base64:)` | Builds a pin from a precomputed Base64 SHA-256 digest string |
| `CertificatePin.base64Digest` | The digest as a Base64 string, for storing in config/Info.plist |
| `PinningResult` | `.trusted`, `.hostNotPinned`, or `.mismatch(host:)` |
| `CertificatePinner` | Holds pins per host and validates certificate chains against them |
| `CertificatePinner.init(pinsByHost:allowsUnpinnedHosts:)` | Configure pins per host; `allowsUnpinnedHosts` controls fail-open vs fail-closed |
| `CertificatePinner.validate(host:chain:)` | Pure validation function — no networking involved |
| `PinningURLSessionDelegate` | `URLSessionDelegate` that enforces a `CertificatePinner` during the TLS handshake |
| `PinningURLSessionDelegate.init(pinner:onFailure:)` | Optional `onFailure` closure for logging/analytics on pin mismatch |

## Examples

### Extracting a pin from a certificate file

```swift
import SwiftUtilsNetworking

let certData = try Data(contentsOf: Bundle.main.url(forResource: "api-example-com", withExtension: "cer")!)
let pin = CertificatePin(certificateData: certData)
print(pin.base64Digest)  // ship this string in config instead of the certificate itself
```

### Configuring pins from stored Base64 digests

```swift
let pins: Set<CertificatePin> = [
    CertificatePin(sha256Base64: "Ejh0hOfQoLdvSPBJmSs5bdM/AKgqZDJm7oOZpFuiHcE=")!, // current leaf
    CertificatePin(sha256Base64: "L/6EYy2/8/wKrzhwK6c0y0h9DrMy5xlF/xg8N7X6X9I=")!, // backup leaf, for rotation
]

let pinner = CertificatePinner(pinsByHost: ["api.example.com": pins])
```

### Wiring pinning into a URLSession

```swift
let delegate = PinningURLSessionDelegate(pinner: pinner) { host in
    Logger.shared.log(.warning, "Certificate pinning failure for \(host)", category: .networking)
}
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

let (data, response) = try await session.data(from: URL(string: "https://api.example.com/data")!)
```

### Allowing some hosts to skip pinning (default behavior)

```swift
// Only api.example.com is pinned; requests to any other host use default trust evaluation.
let pinner = CertificatePinner(pinsByHost: ["api.example.com": pins])
```

### Failing closed for unpinned hosts

```swift
// Any host without explicit pins is rejected outright — useful when every
// endpoint your app talks to is known ahead of time.
let strictPinner = CertificatePinner(pinsByHost: [
    "api.example.com": pins,
    "cdn.example.com": cdnPins,
], allowsUnpinnedHosts: false)
```

### Unit testing without real certificates

```swift
// The validation core takes plain Data, so tests don't need a live TLS handshake.
let leaf = Data("fake-leaf-cert-bytes".utf8)
let pinner = CertificatePinner(pinsByHost: ["api.example.com": [CertificatePin(certificateData: leaf)]])

XCTAssertEqual(pinner.validate(host: "api.example.com", chain: [leaf]), .trusted)
XCTAssertEqual(pinner.validate(host: "api.example.com", chain: [Data("rogue-cert".utf8)]), .mismatch(host: "api.example.com"))
```

### Supporting certificate rotation with multiple pins

```swift
// Pin both the current and the next (backup) certificate so rotating the
// server's certificate doesn't require an app update mid-rollout.
let pins: Set<CertificatePin> = [currentLeafPin, backupLeafPin]
let pinner = CertificatePinner(pinsByHost: ["api.example.com": pins])
```
