import Foundation
import Security
import CommonCrypto

// MARK: - CertificatePin

/// A single pinned certificate, identified by the SHA-256 digest of its DER-encoded bytes.
///
/// Pin the leaf certificate for tight security, or an intermediate/root certificate
/// so pins survive leaf rotation without an app update.
public struct CertificatePin: Hashable, Sendable {

    /// Raw SHA-256 digest (32 bytes) of the certificate's DER representation.
    public let digest: Data

    /// Creates a pin by hashing raw DER-encoded certificate `Data`.
    ///
    /// ```swift
    /// let certData = try Data(contentsOf: certificateFileURL)
    /// let pin = CertificatePin(certificateData: certData)
    /// ```
    public init(certificateData: Data) {
        self.digest = CertificatePin.sha256(certificateData)
    }

    /// Creates a pin from a precomputed, Base64-encoded SHA-256 digest.
    ///
    /// Use this to ship pins as plain strings (e.g. from a config file) without
    /// bundling the certificate itself.
    ///
    /// - Returns: `nil` if `base64Digest` doesn't decode to exactly 32 bytes.
    public init?(sha256Base64 base64Digest: String) {
        guard let data = Data(base64Encoded: base64Digest), data.count == 32 else { return nil }
        self.digest = data
    }

    /// The digest rendered as a Base64 string, suitable for storing in config or `Info.plist`.
    public var base64Digest: String { digest.base64EncodedString() }

    private static func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

// MARK: - PinningResult

/// The outcome of validating a certificate chain against configured pins.
public enum PinningResult: Sendable, Equatable {
    /// At least one certificate in the chain matched a configured pin.
    case trusted
    /// No pins are configured for this host and unpinned hosts are allowed through.
    case hostNotPinned
    /// Pins are configured for this host, but no certificate in the chain matched.
    case mismatch(host: String)
}

// MARK: - CertificatePinner

/// Validates certificate chains against a configured set of SHA-256 pins, per host.
///
/// The validation logic is deliberately decoupled from `URLSession`/`SecTrust` so it
/// can be unit tested with plain `Data` — no real certificates or network calls required.
/// Wire it up to live networking via ``PinningURLSessionDelegate``.
///
/// ```swift
/// let pinner = CertificatePinner(pinsByHost: [
///     "api.example.com": [CertificatePin(sha256Base64: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")!]
/// ])
/// ```
public struct CertificatePinner: Sendable {

    /// Pinned certificates, keyed by lowercased host name.
    public let pinsByHost: [String: Set<CertificatePin>]

    /// When `true` (default), hosts with no configured pins are trusted using the
    /// platform's default evaluation. Set to `false` to fail closed for any host
    /// that doesn't have explicit pins.
    public let allowsUnpinnedHosts: Bool

    /// Creates a pinner.
    /// - Parameters:
    ///   - pinsByHost: Pins to enforce, keyed by host name (case-insensitive).
    ///   - allowsUnpinnedHosts: Whether hosts without configured pins are trusted. Default `true`.
    public init(pinsByHost: [String: Set<CertificatePin>], allowsUnpinnedHosts: Bool = true) {
        self.pinsByHost = pinsByHost.reduce(into: [:]) { result, entry in
            result[entry.key.lowercased(), default: []].formUnion(entry.value)
        }
        self.allowsUnpinnedHosts = allowsUnpinnedHosts
    }

    /// Validates a certificate chain for `host` against the configured pins.
    ///
    /// A match on **any** certificate in the chain (leaf, intermediate, or root) is
    /// accepted, which mirrors common pinning practice and tolerates leaf rotation
    /// when an intermediate or root pin is used instead.
    ///
    /// - Parameters:
    ///   - host: The server host being validated.
    ///   - chain: DER-encoded certificates, typically leaf-first.
    public func validate(host: String, chain: [Data]) -> PinningResult {
        guard let pins = pinsByHost[host.lowercased()], !pins.isEmpty else {
            return allowsUnpinnedHosts ? .hostNotPinned : .mismatch(host: host)
        }

        let chainDigests = Set(chain.map { CertificatePin(certificateData: $0).digest })
        let pinDigests = Set(pins.map(\.digest))
        return chainDigests.isDisjoint(with: pinDigests) ? .mismatch(host: host) : .trusted
    }
}

// MARK: - PinningURLSessionDelegate

/// `URLSessionDelegate` that enforces certificate pinning using a ``CertificatePinner``.
///
/// ```swift
/// let pinner = CertificatePinner(pinsByHost: [
///     "api.example.com": [CertificatePin(sha256Base64: "AAAA...")!]
/// ])
/// let delegate = PinningURLSessionDelegate(pinner: pinner) { host in
///     print("Pinning failure for \(host)")
/// }
/// let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
/// ```
public final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {

    private let pinner: CertificatePinner
    private let onFailure: (@Sendable (String) -> Void)?

    /// Creates a pinning delegate.
    /// - Parameters:
    ///   - pinner: The pin configuration to enforce.
    ///   - onFailure: Called with the offending host whenever validation fails, useful for logging/analytics.
    public init(pinner: CertificatePinner, onFailure: (@Sendable (String) -> Void)? = nil) {
        self.pinner = pinner
        self.onFailure = onFailure
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let chain = Self.certificateChainData(from: serverTrust)

        switch pinner.validate(host: host, chain: chain) {
        case .trusted, .hostNotPinned:
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        case .mismatch:
            onFailure?(host)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private static func certificateChainData(from trust: SecTrust) -> [Data] {
        let certs = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        return certs.map { SecCertificateCopyData($0) as Data }
    }
}
