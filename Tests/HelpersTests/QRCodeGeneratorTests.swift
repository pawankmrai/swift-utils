import XCTest
@testable import SwiftUtilsHelpers

final class QRCodeGeneratorTests: XCTestCase {

    // MARK: - generate(from: String)

    func testGenerateFromStringProducesImage() throws {
        let image = try QRCodeGenerator.generate(from: "https://swift.org", scale: 4)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    func testGenerateFromEmptyStringThrows() {
        XCTAssertThrowsError(try QRCodeGenerator.generate(from: "", scale: 4)) { error in
            XCTAssertEqual(error as? QRCodeGeneratorError, .emptyPayload)
        }
    }

    // MARK: - generate(from: Data)

    func testGenerateFromDataProducesImage() throws {
        let data = "hello world".data(using: .utf8)!
        let image = try QRCodeGenerator.generate(from: data, scale: 4)
        XCTAssertGreaterThan(image.width, 0)
    }

    func testGenerateFromEmptyDataThrows() {
        XCTAssertThrowsError(try QRCodeGenerator.generate(from: Data(), scale: 4)) { error in
            XCTAssertEqual(error as? QRCodeGeneratorError, .emptyPayload)
        }
    }

    // MARK: - Scaling

    func testHigherScaleProducesLargerImage() throws {
        let small = try QRCodeGenerator.generate(from: "scale-test", scale: 2)
        let large = try QRCodeGenerator.generate(from: "scale-test", scale: 8)
        XCTAssertGreaterThan(large.width, small.width)
        XCTAssertGreaterThan(large.height, small.height)
    }

    // MARK: - Correction levels

    func testAllCorrectionLevelsProduceImages() throws {
        for level in QRCodeCorrectionLevel.allCases {
            let image = try QRCodeGenerator.generate(from: "correction-\(level.rawValue)", correctionLevel: level, scale: 4)
            XCTAssertGreaterThan(image.width, 0, "Correction level \(level) failed to render")
        }
    }

    func testHigherCorrectionLevelIsAtLeastAsDenseAsLower() throws {
        // Higher correction levels encode more redundancy and never produce a
        // smaller module grid than lower levels for the same payload.
        let low = try QRCodeGenerator.generate(from: "redundancy-test", correctionLevel: .low, scale: 1)
        let high = try QRCodeGenerator.generate(from: "redundancy-test", correctionLevel: .high, scale: 1)
        XCTAssertGreaterThanOrEqual(high.width, low.width)
    }

    // MARK: - Wi-Fi payload

    func testWifiPayloadFormatsStandardFields() {
        let payload = QRCodeGenerator.wifiPayload(ssid: "HomeNet", password: "s3cret", security: "WPA", isHidden: false)
        XCTAssertEqual(payload, "WIFI:T:WPA;S:HomeNet;P:s3cret;H:false;;")
    }

    func testWifiPayloadOmitsPasswordFieldWhenNil() {
        let payload = QRCodeGenerator.wifiPayload(ssid: "OpenNet", password: nil, security: "nopass", isHidden: false)
        XCTAssertEqual(payload, "WIFI:T:nopass;S:OpenNet;H:false;;")
    }

    func testWifiPayloadMarksHiddenNetworks() {
        let payload = QRCodeGenerator.wifiPayload(ssid: "Hidden", password: "pw", isHidden: true)
        XCTAssertTrue(payload.contains("H:true;;"))
    }

    func testWifiPayloadEscapesSpecialCharacters() {
        let payload = QRCodeGenerator.wifiPayload(ssid: "My;Net:work", password: "p\"a,s\\s", security: "WPA")
        XCTAssertEqual(payload, "WIFI:T:WPA;S:My\\;Net\\:work;P:p\\\"a\\,s\\\\s;H:false;;")
    }

    // MARK: - Round-trip usability

    func testGeneratedWifiPayloadIsEncodable() throws {
        let payload = QRCodeGenerator.wifiPayload(ssid: "TestNet", password: "password123")
        let image = try QRCodeGenerator.generate(from: payload, correctionLevel: .high, scale: 4)
        XCTAssertGreaterThan(image.width, 0)
    }
}
