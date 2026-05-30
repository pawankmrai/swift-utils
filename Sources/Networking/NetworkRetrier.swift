import Foundation

// MARK: - RetryPolicy

/// Defines how a failed network request should be retried.
///
/// `RetryPolicy` encapsulates the maximum number of attempts, delay strategy,
/// and which errors qualify for a retry. Works with any async throwing operation.
///
/// ```swift
/// let policy = RetryPolicy(maxAttempts: 3, strategy: .exponential(base: 1.0, multiplier: 2.0))
/// let data = try await NetworkRetrier.execute(policy: policy) {
///     try await URLSession.shared.data(from: url)
/// }
/// ```
public struct RetryPolicy: Sendable {

    /// Maximum number of attempts (including the initial one).
    public let maxAttempts: Int

    /// Delay strategy between retries.
    public let strategy: DelayStrategy

    /// Determines whether a given error should trigger a retry.
    public let shouldRetry: @Sendable (Error) -> Bool

    /// HTTP status codes that should trigger a retry (e.g. 429, 500, 502, 503, 504).
    public let retryableStatusCodes: Set<Int>

    /// Creates a new retry policy.
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the first. Must be >= 1. Default is 3.
    ///   - strategy: Delay strategy between retries. Default is `.exponential()`.
    ///   - retryableStatusCodes: HTTP status codes that trigger retries. Default is `[408, 429, 500, 502, 503, 504]`.
    ///   - shouldRetry: Custom predicate for deciding if an error is retryable. Default retries `URLError` transient failures.
    public init(
        maxAttempts: Int = 3,
        strategy: DelayStrategy = .exponential(),
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        shouldRetry: @escaping @Sendable (Error) -> Bool = RetryPolicy.defaultShouldRetry
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.strategy = strategy
        self.retryableStatusCodes = retryableStatusCodes
        self.shouldRetry = shouldRetry
    }

    /// Default retryable error check — retries transient `URLError` codes.
    public static func defaultShouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        let retryableCodes: Set<URLError.Code> = [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .notConnectedToInternet,
            .internationalRoamingOff,
            .callIsActive,
            .dataNotAllowed
        ]
        return retryableCodes.contains(urlError.code)
    }

    // MARK: Presets

    /// Aggressive retry: 5 attempts with short exponential backoff.
    public static let aggressive = RetryPolicy(maxAttempts: 5, strategy: .exponential(base: 0.5, multiplier: 1.5))

    /// Conservative retry: 3 attempts with longer delays.
    public static let conservative = RetryPolicy(maxAttempts: 3, strategy: .exponential(base: 2.0, multiplier: 2.0))

    /// Single retry after a fixed 1-second delay.
    public static let once = RetryPolicy(maxAttempts: 2, strategy: .fixed(delay: 1.0))

    /// No retries — execute exactly once.
    public static let none = RetryPolicy(maxAttempts: 1)
}

// MARK: - DelayStrategy

/// Strategy for calculating the delay between retry attempts.
public enum DelayStrategy: Sendable {

    /// Fixed delay between each retry.
    case fixed(delay: TimeInterval)

    /// Exponential backoff: `base * multiplier^(attempt-1)`, capped at `maxDelay`.
    case exponential(base: TimeInterval = 1.0, multiplier: Double = 2.0, maxDelay: TimeInterval = 60.0)

    /// Exponential backoff with random jitter up to `jitterRange` seconds.
    case exponentialWithJitter(base: TimeInterval = 1.0, multiplier: Double = 2.0, maxDelay: TimeInterval = 60.0, jitterRange: TimeInterval = 1.0)

    /// Custom delay computed from the attempt number (0-indexed).
    case custom(@Sendable (Int) -> TimeInterval)

    /// Computes the delay for a given attempt index (0-indexed).
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        switch self {
        case .fixed(let delay):
            return delay

        case .exponential(let base, let multiplier, let maxDelay):
            let computed = base * pow(multiplier, Double(attempt))
            return min(computed, maxDelay)

        case .exponentialWithJitter(let base, let multiplier, let maxDelay, let jitterRange):
            let computed = base * pow(multiplier, Double(attempt))
            let jitter = Double.random(in: 0...jitterRange)
            return min(computed + jitter, maxDelay)

        case .custom(let calculator):
            return calculator(attempt)
        }
    }
}

// MARK: - RetryError

/// Error thrown when all retry attempts are exhausted.
public struct RetryExhaustedError: Error, LocalizedError {

    /// The final error from the last attempt.
    public let lastError: Error

    /// Total number of attempts made.
    public let attempts: Int

    public var errorDescription: String? {
        "All \(attempts) retry attempts exhausted. Last error: \(lastError.localizedDescription)"
    }
}

// MARK: - HTTPRetryError

/// Wrapper error for retryable HTTP status codes.
public struct HTTPRetryableStatusError: Error, LocalizedError {
    /// The HTTP status code.
    public let statusCode: Int

    public var errorDescription: String? {
        "Retryable HTTP status code: \(statusCode)"
    }
}

// MARK: - NetworkRetrier

/// Executes async operations with configurable retry logic.
///
/// Supports generic async throwing closures — useful for network calls,
/// database operations, or any fallible async work.
///
/// ```swift
/// let (data, _) = try await NetworkRetrier.execute(policy: .conservative) {
///     let (data, response) = try await URLSession.shared.data(from: url)
///     guard let http = response as? HTTPURLResponse else { return (data, response) }
///     guard !(policy.retryableStatusCodes.contains(http.statusCode)) else {
///         throw HTTPRetryableStatusError(statusCode: http.statusCode)
///     }
///     return (data, response)
/// }
/// ```
public enum NetworkRetrier {

    /// Executes an operation with the given retry policy.
    /// - Parameters:
    ///   - policy: The retry policy to apply.
    ///   - operation: The async throwing closure to execute.
    /// - Returns: The result of the operation upon success.
    /// - Throws: `RetryExhaustedError` if all attempts fail, or `CancellationError` if the task is cancelled.
    public static func execute<T: Sendable>(
        policy: RetryPolicy,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<policy.maxAttempts {
            try Task.checkCancellation()

            do {
                return try await operation()
            } catch {
                lastError = error

                let isLastAttempt = attempt == policy.maxAttempts - 1
                guard !isLastAttempt, policy.shouldRetry(error) else {
                    if isLastAttempt { break }
                    throw error
                }

                let delay = policy.strategy.delay(forAttempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw RetryExhaustedError(lastError: lastError!, attempts: policy.maxAttempts)
    }

    /// Convenience for retrying a URLSession data request with automatic HTTP status code checking.
    /// - Parameters:
    ///   - request: The URL request to execute.
    ///   - session: The URLSession to use. Defaults to `.shared`.
    ///   - policy: The retry policy. Defaults to `.conservative`.
    /// - Returns: A tuple of `(Data, HTTPURLResponse)`.
    public static func data(
        for request: URLRequest,
        session: URLSession = .shared,
        policy: RetryPolicy = .conservative
    ) async throws -> (Data, HTTPURLResponse) {
        try await execute(policy: policy) {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (data, HTTPURLResponse())
            }
            if policy.retryableStatusCodes.contains(httpResponse.statusCode) {
                throw HTTPRetryableStatusError(statusCode: httpResponse.statusCode)
            }
            return (data, httpResponse)
        }
    }

    /// Convenience for retrying a URLSession data request from a URL.
    /// - Parameters:
    ///   - url: The URL to fetch.
    ///   - session: The URLSession to use. Defaults to `.shared`.
    ///   - policy: The retry policy. Defaults to `.conservative`.
    /// - Returns: A tuple of `(Data, HTTPURLResponse)`.
    public static func data(
        from url: URL,
        session: URLSession = .shared,
        policy: RetryPolicy = .conservative
    ) async throws -> (Data, HTTPURLResponse) {
        try await data(for: URLRequest(url: url), session: session, policy: policy)
    }
}
