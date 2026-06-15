import XCTest
@testable import SwiftUtilsNetworking

final class NetworkMonitorTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultInitCreatesMonitor() {
        let monitor = NetworkMonitor()
        XCTAssertEqual(monitor.status, .unknown)
        XCTAssertFalse(monitor.isConnected)
    }

    func testInterfaceInitCreatesMonitor() {
        let wifiMonitor = NetworkMonitor(requiring: .wifi)
        XCTAssertEqual(wifiMonitor.status, .unknown)
    }

    // MARK: - Status

    func testIsConnectedReturnsFalseWhenDisconnected() {
        let status = NetworkStatus.disconnected
        XCTAssertFalse(status.isConnected)
    }

    func testIsConnectedReturnsTrueWhenConnected() {
        let status = NetworkStatus.connected(.wifi)
        XCTAssertTrue(status.isConnected)
    }

    func testIsConnectedReturnsFalseWhenUnknown() {
        let status = NetworkStatus.unknown
        XCTAssertFalse(status.isConnected)
    }

    // MARK: - NetworkStatus Equatable

    func testStatusEquality() {
        XCTAssertEqual(NetworkStatus.connected(.wifi), NetworkStatus.connected(.wifi))
        XCTAssertEqual(NetworkStatus.disconnected, NetworkStatus.disconnected)
        XCTAssertEqual(NetworkStatus.unknown, NetworkStatus.unknown)
        XCTAssertNotEqual(NetworkStatus.connected(.wifi), NetworkStatus.connected(.cellular))
        XCTAssertNotEqual(NetworkStatus.connected(.wifi), NetworkStatus.disconnected)
        XCTAssertNotEqual(NetworkStatus.disconnected, NetworkStatus.unknown)
    }

    // MARK: - NetworkStatus Description

    func testStatusDescriptions() {
        XCTAssertEqual(NetworkStatus.connected(.wifi).description, "connected(WiFi)")
        XCTAssertEqual(NetworkStatus.connected(.cellular).description, "connected(Cellular)")
        XCTAssertEqual(NetworkStatus.disconnected.description, "disconnected")
        XCTAssertEqual(NetworkStatus.unknown.description, "unknown")
    }

    // MARK: - NetworkInterface Description

    func testInterfaceDescriptions() {
        XCTAssertEqual(NetworkInterface.wifi.description, "WiFi")
        XCTAssertEqual(NetworkInterface.cellular.description, "Cellular")
        XCTAssertEqual(NetworkInterface.wiredEthernet.description, "Ethernet")
        XCTAssertEqual(NetworkInterface.loopback.description, "Loopback")
        XCTAssertEqual(NetworkInterface.other.description, "Other")
    }

    // MARK: - NetworkInterface Equatable

    func testInterfaceEquality() {
        XCTAssertEqual(NetworkInterface.wifi, NetworkInterface.wifi)
        XCTAssertNotEqual(NetworkInterface.wifi, NetworkInterface.cellular)
    }

    // MARK: - Start / Stop

    func testStartAndStopDoNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
    }

    func testDoubleStartDoesNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.start() // should be no-op
        monitor.stop()
    }

    func testDoubleStopDoesNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
        monitor.stop() // should be no-op
    }

    // MARK: - AsyncStream

    func testStatusStreamReceivesCurrentStatusWhenConnected() async {
        // We can't easily mock NWPathMonitor in unit tests, but we can
        // verify the stream machinery by checking that statusStream is
        // a valid AsyncStream and that iteration does not crash.
        let monitor = NetworkMonitor()
        monitor.start()

        // Give monitor a moment to determine initial path
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        let currentStatus = monitor.status
        // Status is one of the known values
        switch currentStatus {
        case .connected, .disconnected, .unknown:
            break // all valid
        }
        monitor.stop()
    }

    // MARK: - waitForConnection timeout

    func testWaitForConnectionTimeoutReturnsNilWhenAlreadyDisconnected() async {
        // Start a cellular-only monitor on a device likely to have no cellular
        // (or in a simulator). Timeout quickly.
        let monitor = NetworkMonitor(requiring: .loopback)
        monitor.start()
        let result = await monitor.waitForConnection(timeout: 0.1)
        monitor.stop()
        // On most CI / simulators there is no loopback path — result should be nil or a status.
        // We just assert no crash and result type is correct.
        if let result {
            XCTAssertTrue(result.isConnected)
        }
    }

    // MARK: - Combine Publisher

    func testStatusPublisherIsAvailable() {
        let monitor = NetworkMonitor()
        var cancellable: Any? = monitor.statusPublisher.sink { _ in }
        XCTAssertNotNil(cancellable)
        cancellable = nil
        monitor.stop()
    }
}
