import Foundation
import Network
import Combine

// MARK: - NetworkStatus

/// The current network connectivity status.
public enum NetworkStatus: Equatable, CustomStringConvertible {
    /// Network is reachable with the specified interface type.
    case connected(NetworkInterface)
    /// Network is not reachable.
    case disconnected
    /// Status has not yet been determined.
    case unknown

    /// Whether the network is currently reachable.
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .connected(let interface): return "connected(\(interface))"
        case .disconnected: return "disconnected"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - NetworkInterface

/// The type of network interface in use.
public enum NetworkInterface: Equatable, CustomStringConvertible {
    case wifi
    case cellular
    case wiredEthernet
    case loopback
    case other

    public var description: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        }
    }

    init(_ interfaceType: NWInterface.InterfaceType) {
        switch interfaceType {
        case .wifi: self = .wifi
        case .cellular: self = .cellular
        case .wiredEthernet: self = .wiredEthernet
        case .loopback: self = .loopback
        default: self = .other
        }
    }
}

// MARK: - NetworkMonitor

/// An async/await-first network connectivity monitor backed by `NWPathMonitor`.
///
/// Use `NetworkMonitor` to observe connectivity changes via an `AsyncStream`,
/// await a single status update, or query the current status synchronously.
///
/// ```swift
/// let monitor = NetworkMonitor()
/// monitor.start()
///
/// for await status in monitor.statusStream {
///     switch status {
///     case .connected(let interface):
///         print("Online via \(interface)")
///     case .disconnected:
///         print("Offline")
///     case .unknown:
///         break
///     }
/// }
/// ```
public final class NetworkMonitor: @unchecked Sendable {

    // MARK: - Public Properties

    /// The most recently observed network status.
    public private(set) var status: NetworkStatus = .unknown

    /// Whether the network is currently connected.
    public var isConnected: Bool { status.isConnected }

    /// An `AsyncStream` that emits a new `NetworkStatus` each time connectivity changes.
    /// Subscribe before calling `start()` to avoid missing the first update.
    public var statusStream: AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            streamContinuations.append(continuation)
            // Immediately emit the current status so subscribers aren't left waiting.
            if status != .unknown {
                continuation.yield(status)
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeStreamContinuation(continuation)
            }
        }
    }

    /// A Combine publisher that emits `NetworkStatus` on connectivity changes.
    public var statusPublisher: AnyPublisher<NetworkStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var streamContinuations: [AsyncStream<NetworkStatus>.Continuation] = []
    private let statusSubject = PassthroughSubject<NetworkStatus, Never>()
    private var isStarted = false
    private let lock = NSLock()

    // MARK: - Init

    /// Creates a monitor that tracks all available network interfaces.
    public init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.swiftutils.networkmonitor", qos: .utility)
    }

    /// Creates a monitor restricted to a specific interface type.
    /// - Parameter interface: The interface to monitor (e.g. `.wifi`, `.cellular`).
    public init(requiring interface: NetworkInterface) {
        switch interface {
        case .wifi:           self.monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        case .cellular:       self.monitor = NWPathMonitor(requiredInterfaceType: .cellular)
        case .wiredEthernet:  self.monitor = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
        case .loopback:       self.monitor = NWPathMonitor(requiredInterfaceType: .loopback)
        case .other:          self.monitor = NWPathMonitor()
        }
        self.queue = DispatchQueue(label: "com.swiftutils.networkmonitor", qos: .utility)
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Starts monitoring network changes. Safe to call multiple times.
    public func start() {
        lock.lock()
        guard !isStarted else { lock.unlock(); return }
        isStarted = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring and cancels all active `AsyncStream` subscriptions.
    public func stop() {
        lock.lock()
        guard isStarted else { lock.unlock(); return }
        isStarted = false
        lock.unlock()

        monitor.cancel()
        streamContinuations.forEach { $0.finish() }
        streamContinuations.removeAll()
    }

    /// Waits asynchronously until the network reaches a connected state, or times out.
    ///
    /// - Parameter timeout: Maximum seconds to wait. Default is 10.
    /// - Returns: The `NetworkStatus` when connectivity is established, or `nil` on timeout.
    @discardableResult
    public func waitForConnection(timeout: TimeInterval = 10) async -> NetworkStatus? {
        if case .connected = status { return status }

        return await withTaskGroup(of: NetworkStatus?.self) { group in
            group.addTask {
                for await s in self.statusStream {
                    if case .connected = s { return s }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            for await result in group {
                if let result { return result }
            }
            return nil
        }
    }

    // MARK: - Private Helpers

    private func handlePathUpdate(_ path: NWPath) {
        let newStatus: NetworkStatus
        if path.status == .satisfied {
            let interface = path.availableInterfaces
                .map { NetworkInterface($0.type) }
                .first ?? .other
            newStatus = .connected(interface)
        } else {
            newStatus = .disconnected
        }

        lock.lock()
        let changed = status != newStatus
        status = newStatus
        lock.unlock()

        guard changed else { return }
        streamContinuations.forEach { $0.yield(newStatus) }
        statusSubject.send(newStatus)
    }

    private func removeStreamContinuation(_ continuation: AsyncStream<NetworkStatus>.Continuation) {
        lock.lock()
        streamContinuations.removeAll { $0 as AnyObject === continuation as AnyObject }
        lock.unlock()
    }
}
