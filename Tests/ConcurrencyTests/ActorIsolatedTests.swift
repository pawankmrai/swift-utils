//
//  ActorIsolatedTests.swift
//  SwiftUtils
//
//  Created by Pawan on 2026-08-02.
//

import XCTest
@testable import SwiftUtilsConcurrency

final class ActorIsolatedTests: XCTestCase {

    func testInitialValueIsReadable() async {
        let box = ActorIsolated(42)
        let value = await box.value
        XCTAssertEqual(value, 42)
    }

    func testSetValueReplacesStorage() async {
        let box = ActorIsolated("hello")
        await box.setValue("world")
        let value = await box.value
        XCTAssertEqual(value, "world")
    }

    func testUpdateMutatesInPlaceAndReturnsResult() async {
        let box = ActorIsolated([1, 2, 3])
        let newCount = await box.update { array -> Int in
            array.append(4)
            return array.count
        }
        XCTAssertEqual(newCount, 4)
        let value = await box.value
        XCTAssertEqual(value, [1, 2, 3, 4])
    }

    func testWithValueSupportsAtomicReadModifyWrite() async {
        let box = ActorIsolated<Set<String>>([])

        let firstInsert = await box.withValue { set -> Bool in
            set.insert("a").inserted
        }
        let secondInsert = await box.withValue { set -> Bool in
            set.insert("a").inserted
        }

        XCTAssertTrue(firstInsert)
        XCTAssertFalse(secondInsert)
        let value = await box.value
        XCTAssertEqual(value, ["a"])
    }

    func testConcurrentUpdatesNeverLoseWrites() async {
        let counter = ActorIsolated(0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    await counter.update { $0 += 1 }
                }
            }
        }

        let total = await counter.value
        XCTAssertEqual(total, 200)
    }

    func testConcurrentAddNeverLosesWrites() async {
        let counter = ActorIsolated(0.0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = await counter.add(0.5)
                }
            }
        }

        let total = await counter.value
        XCTAssertEqual(total, 50.0, accuracy: 0.0001)
    }

    func testCompareAndSetSucceedsWhenExpectedMatches() async {
        let state = ActorIsolated("idle")
        let didTransition = await state.compareAndSet(expected: "idle", newValue: "running")
        XCTAssertTrue(didTransition)
        let value = await state.value
        XCTAssertEqual(value, "running")
    }

    func testCompareAndSetFailsWhenExpectedDoesNotMatch() async {
        let state = ActorIsolated("running")
        let didTransition = await state.compareAndSet(expected: "idle", newValue: "running")
        XCTAssertFalse(didTransition)
        let value = await state.value
        XCTAssertEqual(value, "running")
    }

    func testOnlyOneConcurrentCompareAndSetWins() async {
        let state = ActorIsolated("idle")

        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<50 {
                group.addTask {
                    await state.compareAndSet(expected: "idle", newValue: "running")
                }
            }
            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.filter { $0 }.count, 1)
        let value = await state.value
        XCTAssertEqual(value, "running")
    }

    func testUpdateCanThrowAndRethrows() async {
        struct Boom: Error {}
        let box = ActorIsolated(1)

        do {
            _ = try await box.update { (value: inout Int) -> Int in
                throw Boom()
            }
            XCTFail("Expected update to rethrow")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        let value = await box.value
        XCTAssertEqual(value, 1)
    }
}
