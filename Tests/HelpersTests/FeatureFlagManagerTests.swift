//
//  FeatureFlagManagerTests.swift
//  swift-utils
//
//  Tests for FeatureFlagManager, FeatureFlag, and related types.
//

import XCTest
@testable import SwiftUtils

// MARK: - Test Flag Definitions

private extension FeatureFlag {
    static let testBool = FeatureFlag<Bool>(key: "test_bool", defaultValue: false)
    static let testInt = FeatureFlag<Int>(key: "test_int", defaultValue: 10)
    static let testString = FeatureFlag<String>(key: "test_string", defaultValue: "default")
}

// MARK: - Tests

final class FeatureFlagManagerTests: XCTestCase {
    
    private var manager: FeatureFlagManager!
    
    override func setUp() {
        super.setUp()
        manager = FeatureFlagManager()
    }
    
    override func tearDown() {
        manager.reset()
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Default Values
    
    func testReturnsDefaultValueWhenNoOverrideOrProvider() {
        XCTAssertEqual(manager.value(for: .testBool), false)
        XCTAssertEqual(manager.value(for: .testInt), 10)
        XCTAssertEqual(manager.value(for: .testString), "default")
    }
    
    func testIsEnabledReturnsFalseByDefault() {
        XCTAssertFalse(manager.isEnabled(.testBool))
    }
    
    // MARK: - Local Overrides
    
    func testOverrideReturnsOverriddenValue() {
        manager.setOverride(true, for: .testBool)
        XCTAssertTrue(manager.value(for: .testBool))
        
        manager.setOverride(42, for: .testInt)
        XCTAssertEqual(manager.value(for: .testInt), 42)
        
        manager.setOverride("overridden", for: .testString)
        XCTAssertEqual(manager.value(for: .testString), "overridden")
    }
    
    func testRemoveOverrideRevertsToDefault() {
        manager.setOverride(true, for: .testBool)
        XCTAssertTrue(manager.value(for: .testBool))
        
        manager.removeOverride(for: .testBool)
        XCTAssertFalse(manager.value(for: .testBool))
    }
    
    func testHasOverride() {
        XCTAssertFalse(manager.hasOverride(for: .testBool))
        
        manager.setOverride(true, for: .testBool)
        XCTAssertTrue(manager.hasOverride(for: .testBool))
        
        manager.removeOverride(for: .testBool)
        XCTAssertFalse(manager.hasOverride(for: .testBool))
    }
    
    func testRemoveAllOverrides() {
        manager.setOverride(true, for: .testBool)
        manager.setOverride(99, for: .testInt)
        
        manager.removeAllOverrides()
        
        XCTAssertFalse(manager.value(for: .testBool))
        XCTAssertEqual(manager.value(for: .testInt), 10)
    }
    
    func testAllOverridesReturnsSnapshot() {
        manager.setOverride(true, for: .testBool)
        manager.setOverride(5, for: .testInt)
        
        let overrides = manager.allOverrides()
        XCTAssertEqual(overrides.count, 2)
        XCTAssertNotNil(overrides["test_bool"])
        XCTAssertNotNil(overrides["test_int"])
    }
    
    // MARK: - Provider Resolution
    
    func testProviderValueOverridesDefault() {
        let provider = DictionaryFlagProvider(values: ["test_bool": true])
        manager.registerProvider(provider)
        
        XCTAssertTrue(manager.value(for: .testBool))
    }
    
    func testLocalOverrideTakesPriorityOverProvider() {
        let provider = DictionaryFlagProvider(values: ["test_int": 50])
        manager.registerProvider(provider)
        
        manager.setOverride(100, for: .testInt)
        XCTAssertEqual(manager.value(for: .testInt), 100)
    }
    
    func testMultipleProvidersQueriedInOrder() {
        let first = DictionaryFlagProvider(values: ["test_string": "first"])
        let second = DictionaryFlagProvider(values: ["test_string": "second"])
        
        manager.registerProvider(first)
        manager.registerProvider(second)
        
        // First provider wins
        XCTAssertEqual(manager.value(for: .testString), "first")
    }
    
    func testProviderFallsThroughWhenNoValue() {
        let partial = DictionaryFlagProvider(values: ["test_bool": true])
        manager.registerProvider(partial)
        
        // Provider has test_bool but not test_int → default
        XCTAssertEqual(manager.value(for: .testInt), 10)
    }
    
    func testRemoveAllProviders() {
        let provider = DictionaryFlagProvider(values: ["test_bool": true])
        manager.registerProvider(provider)
        XCTAssertTrue(manager.value(for: .testBool))
        
        manager.removeAllProviders()
        XCTAssertFalse(manager.value(for: .testBool))
    }
    
    // MARK: - Observation
    
    func testObserverCalledOnOverrideChange() {
        let expectation = XCTestExpectation(description: "Observer notified")
        var receivedChange: FlagChange<Bool>?
        
        manager.observe(.testBool) { change in
            receivedChange = change
            expectation.fulfill()
        }
        
        manager.setOverride(true, for: .testBool)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedChange?.key, "test_bool")
        XCTAssertEqual(receivedChange?.oldValue, false)
        XCTAssertEqual(receivedChange?.newValue, true)
    }
    
    func testObserverNotCalledWhenValueUnchanged() {
        manager.setOverride(false, for: .testBool)
        
        var callCount = 0
        manager.observe(.testBool) { _ in
            callCount += 1
        }
        
        // Setting same value should not trigger observer
        manager.setOverride(false, for: .testBool)
        
        // Give a moment for any async callbacks
        let exp = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertEqual(callCount, 0)
    }
    
    func testTokenCancelsObservation() {
        var callCount = 0
        let token = manager.observe(.testBool) { _ in
            callCount += 1
        }
        
        token.cancel()
        manager.setOverride(true, for: .testBool)
        
        let exp = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        
        XCTAssertEqual(callCount, 0)
    }
    
    // MARK: - FeatureFlag Hashable
    
    func testFeatureFlagHashableByKey() {
        let flag1 = FeatureFlag<Bool>(key: "same_key", defaultValue: true)
        let flag2 = FeatureFlag<Bool>(key: "same_key", defaultValue: false)
        
        XCTAssertEqual(flag1, flag2)
        XCTAssertEqual(flag1.hashValue, flag2.hashValue)
    }
    
    func testDifferentKeysAreNotEqual() {
        let flag1 = FeatureFlag<Bool>(key: "key_a", defaultValue: true)
        let flag2 = FeatureFlag<Bool>(key: "key_b", defaultValue: true)
        
        XCTAssertNotEqual(flag1, flag2)
    }
    
    // MARK: - Reset
    
    func testResetClearsEverything() {
        manager.setOverride(true, for: .testBool)
        manager.registerProvider(DictionaryFlagProvider(values: ["test_int": 99]))
        
        manager.reset()
        
        XCTAssertFalse(manager.value(for: .testBool))
        XCTAssertEqual(manager.value(for: .testInt), 10)
        XCTAssertTrue(manager.allOverrides().isEmpty)
    }
}
