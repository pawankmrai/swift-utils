//
//  WebSocketClient.swift
//  SwiftUtils
//
//  An async/await wrapper around URLSessionWebSocketTask that exposes the
//  connection lifecycle and incoming messages as a single AsyncStream,
//  with automatic reconnection and keep-alive pings — no delegate
//  boilerplate required.
//
//  Created by Pawan on 2026-07-13.
//

import Foundation

// MARK: - WebSocketMessage

/// A received WebSocket message, mirroring `URLSessionWebSocketTask.Message`
/// but `Sendable` and easy to pattern-match against.
public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case data(Data)
}

// MARK: - WebSocketEvent

/// Events emitted by `WebSocketClient` as the connection lifecycle progresses.
public enum WebSocketEvent: Sendable {
    /// The socket opened, optionally with the server-negotiated sub-protocol.
    case connected(protocol: String?)
    /// A text or binary message arrived from the server.
    case message(WebSocketMessage)
    /// The socket closed, with the close code and optional reason payload.
    case disconnected(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
    /// A reconnect attempt is about to be made after a connection failure.
    case reconnecting(attempt: Int)
    /// A transport-level error occurred outside the normal close handshake.
    case failure(Error)
}

/// Errors thrown directly by `WebSocketClient` calls (as opposed to events
/// delivered through the `events` stream).
public enum WebSocketError: Error, LocalizedError, Sendable {
    case notConnected
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "The WebSocket is not connected."
        case .encodingFailed: return "Failed to encode the value to send."
        }
    }
}

// MARK: - WebSocketClient

/// A reconnecting, async/await-friendly WebSocket client built on
/// `URLSessionWebSocketTask`.
///
/// ```swift
/// let client = WebSocketClient(url: URL(string: "wss://example.com/socket")!)
/// let events = client.connect()
///
/// Task {
///     for await event in events {
///         switch event {
///         case .connected: print("connected")
///         case .message(.text(let text)): print("received:", text)
///         default: break
///         }
///     }
/// }
///
/// try await client.send("hello")
/// ```
public final class WebSocketClient: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {

    /// Tuning knobs for reconnection and keep-alive behavior.
    public struct Configuration: Sendable {
        /// Seconds between keep-alive pings. Set to `nil` to disable pinging.
        public var pingInterval: TimeInterval?
        /// Whether to automatically reconnect after an unexpected disconnect.
        public var autoReconnect: Bool
        /// Maximum number of consecutive reconnect attempts before giving up.
        public var maxReconnectAttempts: Int
        /// Base delay for exponential backoff between reconnect attempts.
        public var reconnectBaseDelay: TimeInterval
        /// Upper bound on the backoff delay.
        public var reconnectMaxDelay: TimeInterval

        public init(
            pingInterval: TimeInterval? = 25,
            autoReconnect: Bool = true,
            maxReconnectAttempts: Int = 5,
            reconnectBaseDelay: TimeInterval = 1,
            reconnectMaxDelay: TimeInterval = 30
        ) {
            self.pingInterval = pingInterval
            self.autoReconnect = autoReconnect
            self.maxReconnectAttempts = maxReconnectAttempts
            self.reconnectBaseDelay = reconnectBaseDelay
            self.reconnectMaxDelay = reconnectMaxDelay
        }

        public static let `default` = Configuration()
    }

    private let url: URL
    private let headers: [String: String]
    private let configuration: Configuration
    private let sessionConfiguration: URLSessionConfiguration
    private let lock = NSLock()

    /// Lazily created so `self` can be installed as the session delegate —
    /// required for `didOpenWithProtocol` / `didCloseWith` callbacks to fire.
    private lazy var session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)

    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<WebSocketEvent>.Continuation?
    private var isManuallyClosed = false
    private var isHandlingDisconnect = false
    private var reconnectAttempt = 0
    private var pingTask: Task<Void, Never>?

    /// Creates a client for the given endpoint. No connection is made until `connect()` is called.
    public init(
        url: URL,
        headers: [String: String] = [:],
        configuration: Configuration = .default,
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.url = url
        self.headers = headers
        self.configuration = configuration
        self.sessionConfiguration = sessionConfiguration
        super.init()
    }

    /// Opens the connection and returns a stream of lifecycle events and
    /// incoming messages. Calling this again replaces any prior stream.
    @discardableResult
    public func connect() -> AsyncStream<WebSocketEvent> {
        lock.lock()
        isManuallyClosed = false
        reconnectAttempt = 0
        lock.unlock()

        let stream = AsyncStream<WebSocketEvent> { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.teardown() }
        }
        openTask()
        return stream
    }

    /// Sends a text frame. Throws `WebSocketError.notConnected` if no socket is open.
    public func send(_ text: String) async throws {
        try await currentTask().send(.string(text))
    }

    /// Sends a binary frame. Throws `WebSocketError.notConnected` if no socket is open.
    public func send(_ data: Data) async throws {
        try await currentTask().send(.data(data))
    }

    /// Encodes `value` as JSON and sends it as a text frame.
    public func send<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) async throws {
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            throw WebSocketError.encodingFailed
        }
        try await send(text)
    }

    /// Closes the connection and disables auto-reconnect. Safe to call multiple times.
    public func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) {
        lock.lock()
        isManuallyClosed = true
        let activeTask = task
        lock.unlock()
        activeTask?.cancel(with: closeCode, reason: reason)
        teardown()
    }

    /// Decodes a `WebSocketMessage` as JSON. Both `.text` and `.data` payloads are supported.
    public static func decode<T: Decodable>(
        _ message: WebSocketMessage,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let data: Data
        switch message {
        case .text(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Private

    private func currentTask() throws -> URLSessionWebSocketTask {
        lock.lock()
        defer { lock.unlock() }
        guard let task, task.state == .running else { throw WebSocketError.notConnected }
        return task
    }

    private func openTask() {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let newTask = session.webSocketTask(with: request)
        lock.lock()
        task = newTask
        isHandlingDisconnect = false
        lock.unlock()
        newTask.resume()
        receiveNext()
        startPingLoop()
    }

    private func receiveNext() {
        lock.lock()
        let activeTask = task
        lock.unlock()
        activeTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.continuation?.yield(.message(message.asWebSocketMessage))
                self.receiveNext()
            case .failure(let error):
                self.continuation?.yield(.failure(error))
                self.handleDisconnect()
            }
        }
    }

    private func startPingLoop() {
        guard let interval = configuration.pingInterval else { return }
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.task?.sendPing { _ in }
            }
        }
    }

    /// Runs once per disconnect, guarded against being invoked twice for the
    /// same failure (both the receive-loop error path and the delegate's
    /// `didCloseWith` callback can fire for a single dropped connection).
    private func handleDisconnect(code: URLSessionWebSocketTask.CloseCode = .invalid, reason: Data? = nil) {
        lock.lock()
        if isHandlingDisconnect {
            lock.unlock()
            return
        }
        isHandlingDisconnect = true
        let manuallyClosed = isManuallyClosed
        lock.unlock()

        pingTask?.cancel()
        continuation?.yield(.disconnected(code: code, reason: reason))

        guard !manuallyClosed, configuration.autoReconnect else {
            continuation?.finish()
            return
        }

        lock.lock()
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        lock.unlock()

        guard attempt <= configuration.maxReconnectAttempts else {
            continuation?.finish()
            return
        }

        let delay = min(configuration.reconnectMaxDelay, configuration.reconnectBaseDelay * pow(2, Double(attempt - 1)))
        continuation?.yield(.reconnecting(attempt: attempt))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.openTask()
        }
    }

    private func teardown() {
        pingTask?.cancel()
        lock.lock()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        lock.unlock()
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        lock.lock()
        reconnectAttempt = 0
        lock.unlock()
        continuation?.yield(.connected(protocol: `protocol`))
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        handleDisconnect(code: closeCode, reason: reason)
    }
}

private extension URLSessionWebSocketTask.Message {
    var asWebSocketMessage: WebSocketMessage {
        switch self {
        case .string(let text): return .text(text)
        case .data(let data): return .data(data)
        @unknown default: return .data(Data())
        }
    }
}
