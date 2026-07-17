//
//  SSEClient.swift
//  SwiftUtils
//
//  An async/await client for Server-Sent Events (text/event-stream) built on
//  URLSession's byte-streaming API. Parses the SSE wire format (id/event/data/
//  retry fields, multi-line data, comments) into typed messages delivered
//  through a single AsyncStream, with Last-Event-ID resumption and
//  exponential-backoff auto-reconnect — no third-party dependency required.
//
//  Created by Pawan on 2026-07-17.
//

import Foundation

// MARK: - SSEMessage

/// A single parsed Server-Sent Event, assembled from one or more
/// `field: value` lines terminated by a blank line, per the WHATWG spec.
public struct SSEMessage: Sendable, Equatable {
    /// The event's `id:` field, if present. Echoed back as `Last-Event-ID` on reconnect.
    public let id: String?
    /// The event's `event:` field. Defaults to `"message"` when omitted.
    public let event: String
    /// The event's `data:` field(s), joined with `\n` for multi-line payloads.
    public let data: String
    /// The event's `retry:` field in milliseconds, if the server requested a new reconnect delay.
    public let retry: Int?
}

// MARK: - SSEEvent

/// Lifecycle events emitted by `SSEClient` as the stream progresses.
public enum SSEEvent: Sendable {
    /// The HTTP response arrived with a success status and streaming has begun.
    case open
    /// A complete event was parsed from the stream.
    case message(SSEMessage)
    /// The connection dropped and a reconnect attempt is about to be made.
    case reconnecting(attempt: Int)
    /// A transport or HTTP-level error occurred.
    case failure(Error)
    /// The stream ended permanently (manual disconnect, or reconnect attempts exhausted).
    case closed
}

/// Errors thrown directly by `SSEClient`, distinct from errors delivered through the `events` stream.
public enum SSEClientError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server did not return a valid HTTP response."
        case .httpError(let code):
            return "The server responded with status code \(code)."
        }
    }
}

// MARK: - SSEClient

/// A reconnecting, async/await-friendly Server-Sent Events client built on
/// `URLSession.bytes(for:)`.
///
/// ```swift
/// let client = SSEClient(url: URL(string: "https://example.com/stream")!)
///
/// Task {
///     for await event in client.connect() {
///         switch event {
///         case .open: print("connected")
///         case .message(let message): print(message.event, message.data)
///         default: break
///         }
///     }
/// }
/// ```
public final class SSEClient: @unchecked Sendable {

    /// Tuning knobs for reconnection behavior.
    public struct Configuration: Sendable {
        /// Whether to automatically reconnect after the stream drops or the server closes it.
        public var autoReconnect: Bool
        /// Maximum number of consecutive reconnect attempts before giving up.
        public var maxReconnectAttempts: Int
        /// Base delay for exponential backoff between reconnect attempts, used unless the server sends `retry:`.
        public var reconnectBaseDelay: TimeInterval
        /// Upper bound on the backoff delay.
        public var reconnectMaxDelay: TimeInterval

        public init(
            autoReconnect: Bool = true,
            maxReconnectAttempts: Int = 10,
            reconnectBaseDelay: TimeInterval = 1,
            reconnectMaxDelay: TimeInterval = 30
        ) {
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
    private let session: URLSession
    private let lock = NSLock()

    private var continuation: AsyncStream<SSEEvent>.Continuation?
    private var streamTask: Task<Void, Never>?
    private var lastEventID: String?
    private var serverRetryOverride: TimeInterval?
    private var isManuallyClosed = false
    private var reconnectAttempt = 0

    /// Creates a client for the given endpoint. No request is made until `connect()` is called.
    public init(
        url: URL,
        headers: [String: String] = [:],
        configuration: Configuration = .default,
        session: URLSession = .shared
    ) {
        self.url = url
        self.headers = headers
        self.configuration = configuration
        self.session = session
    }

    /// Opens the stream and returns an `AsyncStream` of lifecycle events and messages.
    /// Calling this again replaces any prior stream and resets the reconnect counter.
    @discardableResult
    public func connect() -> AsyncStream<SSEEvent> {
        lock.lock()
        isManuallyClosed = false
        reconnectAttempt = 0
        lock.unlock()

        let stream = AsyncStream<SSEEvent> { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in self?.teardown() }
        }
        run()
        return stream
    }

    /// Closes the stream and disables auto-reconnect. Safe to call multiple times.
    public func disconnect() {
        lock.lock()
        isManuallyClosed = true
        lock.unlock()
        teardown()
        continuation?.yield(.closed)
        continuation?.finish()
    }

    /// Decodes an `SSEMessage`'s `data` payload as JSON.
    public static func decode<T: Decodable>(
        _ message: SSEMessage,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decoder.decode(T.self, from: Data(message.data.utf8))
    }

    // MARK: - Private

    private func run() {
        streamTask = Task { [weak self] in
            await self?.readStream()
        }
    }

    private func readStream() async {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        lock.lock()
        let eventID = lastEventID
        lock.unlock()
        if let eventID { request.setValue(eventID, forHTTPHeaderField: "Last-Event-ID") }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw SSEClientError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw SSEClientError.httpError(statusCode: http.statusCode) }

            lock.lock(); reconnectAttempt = 0; lock.unlock()
            continuation?.yield(.open)

            var idBuffer: String?
            var eventBuffer = "message"
            var dataLines: [String] = []
            var retryBuffer: Int?

            for try await line in bytes.lines {
                if Task.isCancelled { return }

                if line.isEmpty {
                    if !dataLines.isEmpty {
                        let message = SSEMessage(id: idBuffer, event: eventBuffer, data: dataLines.joined(separator: "\n"), retry: retryBuffer)
                        if let idBuffer { lock.lock(); lastEventID = idBuffer; lock.unlock() }
                        continuation?.yield(.message(message))
                    }
                    idBuffer = nil
                    eventBuffer = "message"
                    dataLines = []
                    continue
                }
                if line.hasPrefix(":") { continue } // comment / heartbeat

                let (field, value) = Self.parseField(line)
                switch field {
                case "id": idBuffer = value
                case "event": eventBuffer = value.isEmpty ? "message" : value
                case "data": dataLines.append(value)
                case "retry":
                    if let millis = Int(value) {
                        retryBuffer = millis
                        lock.lock(); serverRetryOverride = TimeInterval(millis) / 1000; lock.unlock()
                    }
                default: break
                }
            }
            handleStreamEnd()
        } catch {
            if Task.isCancelled { return }
            continuation?.yield(.failure(error))
            handleStreamEnd()
        }
    }

    private func handleStreamEnd() {
        lock.lock()
        let manuallyClosed = isManuallyClosed
        lock.unlock()

        guard !manuallyClosed, configuration.autoReconnect else {
            continuation?.yield(.closed)
            continuation?.finish()
            return
        }

        lock.lock()
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let override = serverRetryOverride
        lock.unlock()

        guard attempt <= configuration.maxReconnectAttempts else {
            continuation?.yield(.closed)
            continuation?.finish()
            return
        }

        let backoff = min(configuration.reconnectMaxDelay, configuration.reconnectBaseDelay * pow(2, Double(attempt - 1)))
        let delay = override ?? backoff
        continuation?.yield(.reconnecting(attempt: attempt))

        streamTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.readStream()
        }
    }

    private func teardown() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Splits a raw SSE line into its field name and value, stripping a single leading space from the value per spec.
    private static func parseField(_ line: String) -> (field: String, value: String) {
        guard let colonIndex = line.firstIndex(of: ":") else { return (line, "") }
        let field = String(line[line.startIndex..<colonIndex])
        var value = String(line[line.index(after: colonIndex)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        return (field, value)
    }
}
