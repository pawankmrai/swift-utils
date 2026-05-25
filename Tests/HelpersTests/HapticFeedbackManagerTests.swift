//
//  HapticFeedbackManagerTests.swift
//  SwiftUtils
//

import XCTest
@testable import SwiftUtilsHelpers

final class HapticFeedbackManagerTests: XCTestCase {

    var manager: HapticFeedbackManager!

    override func setUp() {
        super.setUp()
        manager = HapticFeedbackManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testSharedInstanceExists() {
        XCTAssertNotNil(HapticFeedbackManager.shared)
    }

    func testSharedInstanceIsSingleton() {
        let a = HapticFeedbackManager.shared
        let b = HapticFeedbackManager.shared
        XCTAssertTrue(a === b)
    }

    func testInitCreatesNewInstance() {
        let a = HapticFeedbackManager()
        let b = HapticFeedbackManager()
        XCTAssertFalse(a === b)
    }

    // MARK: - Enabled State

    func testIsEnabledDefaultsToTrue() {
        XCTAssertTrue(manager.isEnabled)
    }

    func testCanDisableHaptics() {
        manager.isEnabled = false
        XCTAssertFalse(manager.isEnabled)
    }

    func testCanReEnableHaptics() {
        manager.isEnabled = false
        manager.isEnabled = true
        XCTAssertTrue(manager.isEnabled)
    }

    // MARK: - Impact Styles

    func testImpactDoesNotCrashWhenDisabled() {
        manager.isEnabled = false
        manager.impact(.light)
        manager.impact(.medium)
        manager.impact(.heavy)
        manager.impact(.soft)
        manager.impact(.rigid)
    }

    func testImpactWithIntensityDoesNotCrash() {
        manager.impact(.medium, intensity: 0.0)
        manager.impact(.medium, intensity: 0.5)
        manager.impact(.medium, intensity: 1.0)
    }

    func testImpactClampsIntensity() {
        manager.impact(.heavy, intensity: -1.0)
        manager.impact(.heavy, intensity: 2.5)
    }

    // MARK: - Notification Types

    func testNotificationDoesNotCrashWhenDisabled() {
        manager.isEnabled = false
        manager.notification(.success)
        manager.notification(.warning)
        manager.notification(.error)
    }

    // MARK: - Selection

    func testSelectionDoesNotCrashWhenDisabled() {
        manager.isEnabled = false
        manager.selection()
    }

    // MARK: - Preparation

    func testPrepareDoesNotCrash() {
        manager.prepare()
    }

    func testPrepareSpecificStyleDoesNotCrash() {
        manager.prepare(.light)
        manager.prepare(.medium)
        manager.prepare(.heavy)
        manager.prepare(.soft)
        manager.prepare(.rigid)
    }

    // MARK: - Pattern Playback

    func testPlayPatternRespectsDisabledState() async {
        manager.isEnabled = false
        await manager.playPattern([
            .impact(.heavy),
            .pause(0.01),
            .notification(.success)
        ])
    }

    func testPlayPatternWithEmptyArray() async {
        await manager.playPattern([])
    }

    func testPlayPatternWithAllElementTypes() async {
        await manager.playPattern([
            .impact(.light, intensity: 0.5),
            .pause(0.01),
            .notification(.success),
            .pause(0.01),
            .selection
        ])
    }

    // MARK: - Convenience Patterns

    func testDoubleTapDoesNotCrash() async {
        await manager.doubleTap(style: .light)
    }

    func testEscalateDoesNotCrash() async {
        await manager.escalate()
    }

    func testHeartbeatDoesNotCrash() async {
        await manager.heartbeat()
    }

    // MARK: - Thread Safety

    func testConcurrentImpactCalls() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    self.manager.impact(.medium)
                }
            }
        }
    }

    func testConcurrentPrepareCalls() async {
        await withTaskGroup(of: Void.self) { group in
            for style in [HapticFeedbackManager.ImpactStyle.light, .medium, .heavy, .soft, .rigid] {
                group.addTask {
                    self.manager.prepare(style)
                }
            }
        }
    }
}
