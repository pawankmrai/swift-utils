//
//  AsyncBroadcasterTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-10-03.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class AsyncBroadcasterTests: XCTestCase {

    private func collect<T>(_ stream: AsyncStream<T>) async -> [T] {
        var values: [T] = []
        for await value in stream { values.append(value) }
        return values
    }

    func testEverySubscriberReceivesEveryElement() async {
        let broadcaster = AsyncBroadcaster<Int>()
        let a = broadcaster.stream()
        let b = broadcaster.stream()
        XCTAssertEqual(broadcaster.subscriberCount, 2)

        broadcaster.send(1)
        broadcaster.send(2)
        broadcaster.send(3)
        broadcaster.finish()

        let valuesA = await collect(a)
        let valuesB = await collect(b)
        XCTAssertEqual(valuesA, [1, 2, 3])
        XCTAssertEqual(valuesB, [1, 2, 3])
    }

    func testNoReplayByDefault() async {
        let broadcaster = AsyncBroadcaster<Int>()
        broadcaster.send(1)
        let late = broadcaster.stream()
        broadcaster.send(2)
        broadcaster.finish()

        let values = await collect(late)
        XCTAssertEqual(values, [2])
        XCTAssertNil(broadcaster.latestValue)
    }

    func testReplayDeliversMostRecentElementsToNewSubscribers() async {
        let broadcaster = AsyncBroadcaster<Int>(replay: 2)
        broadcaster.send(1)
        broadcaster.send(2)
        broadcaster.send(3)
        XCTAssertEqual(broadcaster.latestValue, 3)

        let late = broadcaster.stream()
        broadcaster.send(4)
        broadcaster.finish()

        let values = await collect(late)
        XCTAssertEqual(values, [2, 3, 4])
    }

    func testSubscribingAfterFinishYieldsReplayThenEnds() async {
        let broadcaster = AsyncBroadcaster<String>(replay: 1)
        broadcaster.send("final")
        broadcaster.finish()

        let values = await collect(broadcaster.stream())
        XCTAssertEqual(values, ["final"])
        XCTAssertEqual(broadcaster.subscriberCount, 0)
    }

    func testSendAfterFinishIsIgnored() async {
        let broadcaster = AsyncBroadcaster<Int>(replay: 1)
        let stream = broadcaster.stream()
        broadcaster.send(1)
        broadcaster.finish()
        broadcaster.send(2)

        XCTAssertTrue(broadcaster.isFinished)
        XCTAssertEqual(broadcaster.latestValue, 1)
        let values = await collect(stream)
        XCTAssertEqual(values, [1])
    }

    func testFinishIsIdempotent() {
        let broadcaster = AsyncBroadcaster<Int>()
        _ = broadcaster.stream()
        broadcaster.finish()
        broadcaster.finish()
        XCTAssertTrue(broadcaster.isFinished)
        XCTAssertEqual(broadcaster.subscriberCount, 0)
    }

    func testCancelledSubscriberIsRemoved() async throws {
        let broadcaster = AsyncBroadcaster<Int>()
        let stream = broadcaster.stream()
        let task = Task { for await _ in stream {} }
        XCTAssertEqual(broadcaster.subscriberCount, 1)

        task.cancel()
        await task.value

        // onTermination runs as part of cancellation; allow a short grace period.
        for _ in 0..<50 where broadcaster.subscriberCount > 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(broadcaster.subscriberCount, 0)
    }

    func testBufferingNewestKeepsOnlyLatestForSlowConsumers() async {
        let broadcaster = AsyncBroadcaster<Int>(bufferingPolicy: .bufferingNewest(1))
        let stream = broadcaster.stream()
        (1...5).forEach(broadcaster.send)
        broadcaster.finish()

        let values = await collect(stream)
        XCTAssertEqual(values, [5])
    }

    func testConcurrentSendsAreAllDelivered() async {
        let broadcaster = AsyncBroadcaster<Int>()
        let stream = broadcaster.stream()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { broadcaster.send(i) }
            }
        }
        broadcaster.finish()

        let values = await collect(stream)
        XCTAssertEqual(values.count, 100)
        XCTAssertEqual(Set(values), Set(0..<100))
    }
}
