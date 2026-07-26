//
//  AsyncSequence+Combining.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-07-26.
//

import Foundation

// MARK: - merge

/// Merges two or more homogeneous `AsyncSequence`s into a single
/// `AsyncThrowingStream` that yields each upstream element as soon as it
/// arrives, interleaved across all sources in whatever order they produce
/// values.
///
/// The returned stream finishes once every source has finished. If any
/// source throws, the remaining sources are cancelled and the error is
/// propagated through the stream.
///
/// ```swift
/// let events = merge(sensorAStream, sensorBStream, sensorCStream)
/// for try await reading in events {
///     print("New reading:", reading)
/// }
/// ```
///
/// - Parameter sequences: The sequences to merge. Iteration of the
///   returned stream cancels all of them.
/// - Returns: An `AsyncThrowingStream` interleaving elements from every source.
public func merge<S: AsyncSequence>(
    _ sequences: S...
) -> AsyncThrowingStream<S.Element, Error> where S: Sendable, S.Element: Sendable {
    merge(sequences)
}

/// Array-based overload of ``merge(_:)-(S...)``, for when the sequences to
/// merge are already collected (e.g. built dynamically).
public func merge<S: AsyncSequence>(
    _ sequences: [S]
) -> AsyncThrowingStream<S.Element, Error> where S: Sendable, S.Element: Sendable {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for sequence in sequences {
                        group.addTask {
                            for try await element in sequence {
                                continuation.yield(element)
                            }
                        }
                    }
                    try await group.waitForAll()
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

// MARK: - combineLatest

/// Combines two `AsyncSequence`s into a stream of tuples containing the
/// most recent value from each source, re-emitting a new tuple whenever
/// *either* source produces a value — once both have produced at least one.
///
/// Mirrors the behavior of Combine's `combineLatest`, but for `AsyncSequence`.
/// Useful for driving derived UI state off multiple independent streams,
/// e.g. a search query and a filter selection.
///
/// ```swift
/// let stream = combineLatest(queryStream, filterStream)
/// for try await (query, filter) in stream {
///     await search(query, filter: filter)
/// }
/// ```
///
/// - Parameters:
///   - a: The first source sequence.
///   - b: The second source sequence.
/// - Returns: An `AsyncThrowingStream` of `(A.Element, B.Element)` pairs.
public func combineLatest<A: AsyncSequence, B: AsyncSequence>(
    _ a: A,
    _ b: B
) -> AsyncThrowingStream<(A.Element, B.Element), Error>
where A: Sendable, B: Sendable, A.Element: Sendable, B.Element: Sendable {
    AsyncThrowingStream { continuation in
        let state = CombineLatestState<A.Element, B.Element>()
        let task = Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await element in a {
                            if let pair = await state.updateA(element) {
                                continuation.yield(pair)
                            }
                        }
                    }
                    group.addTask {
                        for try await element in b {
                            if let pair = await state.updateB(element) {
                                continuation.yield(pair)
                            }
                        }
                    }
                    try await group.waitForAll()
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Actor holding the "latest value from each side" state for
/// ``combineLatest(_:_:)``, so concurrent updates from both source tasks
/// stay data-race free.
private actor CombineLatestState<A: Sendable, B: Sendable> {
    private var latestA: A?
    private var latestB: B?

    func updateA(_ value: A) -> (A, B)? {
        latestA = value
        guard let b = latestB else { return nil }
        return (value, b)
    }

    func updateB(_ value: B) -> (A, B)? {
        latestB = value
        guard let a = latestA else { return nil }
        return (a, value)
    }
}

// MARK: - zip

/// Zips two `AsyncSequence`s together in lockstep, producing one tuple per
/// pair of elements pulled from each source. The returned stream finishes
/// as soon as either source is exhausted (matching `Swift.zip`'s semantics
/// for regular sequences).
///
/// ```swift
/// let paired = zip(namesStream, scoresStream)
/// for try await (name, score) in paired {
///     print("\(name): \(score)")
/// }
/// ```
///
/// - Parameters:
///   - a: The first source sequence.
///   - b: The second source sequence.
/// - Returns: An `AsyncThrowingStream` of `(A.Element, B.Element)` pairs,
///   one per successful `next()` from both sources.
public func zip<A: AsyncSequence, B: AsyncSequence>(
    _ a: A,
    _ b: B
) -> AsyncThrowingStream<(A.Element, B.Element), Error>
where A: Sendable, B: Sendable, A.Element: Sendable, B.Element: Sendable {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var iteratorA = a.makeAsyncIterator()
                var iteratorB = b.makeAsyncIterator()
                while true {
                    async let nextA = iteratorA.next()
                    async let nextB = iteratorB.next()
                    guard let elementA = try await nextA, let elementB = try await nextB else {
                        break
                    }
                    continuation.yield((elementA, elementB))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
