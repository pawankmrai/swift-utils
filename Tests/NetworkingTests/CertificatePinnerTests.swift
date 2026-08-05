import XCTest
@testable import SwiftUtilsNetworking

final class CertificatePinnerTests: XCTestCase {

    // MARK: - Fixtures

    /// Deterministic "fake certificate" bytes for a given seed — not real DER, just
    /// distinct byte sequences we can hash and compare.
    private func fakeCertificate(_ seed: String) -> Data {
        Data(seed.utf8)
    }

    // MARK: - CertificatePin

    func testCertificatePinFromDataIsDeterministic() {
        let cert = fakeCertificate("leaf")
        let pinA = CertificatePin(certificateData: cert)
        let pinB = CertificatePin(certificateData: cert)
        XCTAssertEqual(pinA, pinB)
        XCTAssertEqual(pinA.digest.count, 32, "SHA-256 digest must be 32 bytes")
    }

    func testCertificatePinDiffersForDifferentCertificates() {
        let pinA = CertificatePin(certificateData: fakeCertificate("leaf"))
        let pinB = CertificatePin(certificateData: fakeCertificate("intermediate"))
        XCTAssertNotEqual(pinA, pinB)
    }

    func testCertificatePinFromValidBase64Digest() {
        let original = CertificatePin(certificateData: fakeCertificate("leaf"))
        let restored = CertificatePin(sha256Base64: original.base64Digest)
        XCTAssertEqual(restored, original)
    }

    func testCertificatePinFromBase64RejectsWrongLength() {
        // 4 bytes, not the required 32.
        let tooShort = Data([1, 2, 3, 4]).base64EncodedString()
        XCTAssertNil(CertificatePin(sha256Base64: tooShort))
    }

    func testCertificatePinFromBase64RejectsInvalidBase64() {
        XCTAssertNil(CertificatePin(sha256Base64: "not-valid-base64!!!"))
    }

    // MARK: - CertificatePinner.validate — matches

    func testValidateTrustedWhenLeafMatchesPin() {
        let leaf = fakeCertificate("leaf")
        let pin = CertificatePin(certificateData: leaf)
        let pinner = CertificatePinner(pinsByHost: ["api.example.com": [pin]])

        let result = pinner.validate(host: "api.example.com", chain: [leaf, fakeCertificate("intermediate")])
        XCTAssertEqual(result, .trusted)
    }

    func testValidateTrustedWhenIntermediateMatchesPin() {
        let leaf = fakeCertificate("leaf")
        let intermediate = fakeCertificate("intermediate")
        let pin = CertificatePin(certificateData: intermediate)
        let pinner = CertificatePinner(pinsByHost: ["api.example.com": [pin]])

        let result = pinner.validate(host: "api.example.com", chain: [leaf, intermediate])
        XCTAssertEqual(result, .trusted)
    }

    func testValidateHostMatchingIsCaseInsensitive() {
        let leaf = fakeCertificate("leaf")
        let pinner = CertificatePinner(pinsByHost: ["API.Example.com": [CertificatePin(certificateData: leaf)]])

        let result = pinner.validate(host: "api.example.com", chain: [leaf])
        XCTAssertEqual(result, .trusted)
    }

    // MARK: - CertificatePinner.validate — mismatches

    func testValidateMismatchWhenNoCertificateMatches() {
        let pin = CertificatePin(certificateData: fakeCertificate("expected"))
        let pinner = CertificatePinner(pinsByHost: ["api.example.com": [pin]])

        let result = pinner.validate(host: "api.example.com", chain: [fakeCertificate("attacker")])
        XCTAssertEqual(result, .mismatch(host: "api.example.com"))
    }

    func testValidateMismatchWhenChainIsEmpty() {
        let pin = CertificatePin(certificateData: fakeCertificate("expected"))
        let pinner = CertificatePinner(pinsByHost: ["api.example.com": [pin]])

        let result = pinner.validate(host: "api.example.com", chain: [])
        XCTAssertEqual(result, .mismatch(host: "api.example.com"))
    }

    // MARK: - Unpinned hosts

    func testValidateAllowsUnpinnedHostByDefault() {
        let pinner = CertificatePinner(pinsByHost: ["api.example.com": [CertificatePin(certificateData: fakeCertificate("leaf"))]])

        let result = pinner.validate(host: "other.example.com", chain: [fakeCertificate("anything")])
        XCTAssertEqual(result, .hostNotPinned)
    }

    func testValidateFailsClosedForUnpinnedHostWhenConfigured() {
        let pinner = CertificatePinner(
            pinsByHost: ["api.example.com": [CertificatePin(certificateData: fakeCertificate("leaf"))]],
            allowsUnpinnedHosts: false
        )

        let result = pinner.validate(host: "other.example.com", chain: [fakeCertificate("anything")])
        XCTAssertEqual(result, .mismatch(host: "other.example.com"))
    }

    func testValidateMismatchWhenHostConfiguredWithEmptyPinSet() {
        let pinner = CertificatePinner(pinsByHost: ["api.example.com": []])

        let result = pinner.validate(host: "api.example.com", chain: [fakeCertificate("leaf")])
        XCTAssertEqual(result, .mismatch(host: "api.example.com"))
    }

    // MARK: - Multiple pins per host (rotation support)

    func testValidateTrustedWithBackupPin() {
        let currentLeaf = fakeCertificate("current-leaf")
        let backupLeaf = fakeCertificate("backup-leaf")
        let pinner = CertificatePinner(pinsByHost: [
            "api.example.com": [
                CertificatePin(certificateData: currentLeaf),
                CertificatePin(certificateData: backupLeaf),
            ]
        ])

        let result = pinner.validate(host: "api.example.com", chain: [backupLeaf])
        XCTAssertEqual(result, .trusted)
    }
}
