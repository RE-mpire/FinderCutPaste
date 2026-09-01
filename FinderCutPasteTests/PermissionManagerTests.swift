//
//  PermissionManagerTests.swift
//  FinderCutPaste
//
//  Created by Kyle Y on 2026-08-19.
//

import XCTest
import Combine
@testable import FinderCutPaste

// MARK: - Test doubles

final class MockAccessibilityAuthorizer: AccessibilityAuthorizing {
    var isTrustedValue = false
    private(set) var requestTrustCallCount = 0
    private(set) var lastPromptingUser: Bool?

    func isTrusted() -> Bool {
        isTrustedValue
    }

    @discardableResult
    func requestTrust(promptingUser: Bool) -> Bool {
        requestTrustCallCount += 1
        lastPromptingUser = promptingUser
        return isTrustedValue
    }
}

final class MockTimerToken: TimerToken {
    private(set) var invalidateCallCount = 0
    func invalidate() {
        invalidateCallCount += 1
    }
}

final class MockTimerScheduler: TimerScheduling {
    let token = MockTimerToken()
    private(set) var scheduleCallCount = 0
    private(set) var lastInterval: TimeInterval?
    private var handler: (() -> Void)?

    func scheduleRepeating(interval: TimeInterval, handler: @escaping () -> Void) -> TimerToken {
        scheduleCallCount += 1
        lastInterval = interval
        self.handler = handler
        return token
    }

    /// Simulates one tick of the poll timer firing.
    func fireTick() {
        handler?()
    }
}

// MARK: - Tests

final class PermissionManagerTests: XCTestCase {
    private var authorizer: MockAccessibilityAuthorizer!
    private var scheduler: MockTimerScheduler!
    private var sut: PermissionManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        authorizer = MockAccessibilityAuthorizer()
        scheduler = MockTimerScheduler()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        authorizer = nil
        scheduler = nil
        super.tearDown()
    }

    private func makeSUT(initiallyTrusted: Bool) -> PermissionManager {
        authorizer.isTrustedValue = initiallyTrusted
        return PermissionManager(authorizer: authorizer, scheduler: scheduler)
    }

    // MARK: Initial state

    func test_init_whenAuthorizerTrusted_startsGranted() {
        sut = makeSUT(initiallyTrusted: true)
        XCTAssertTrue(sut.hasAccessibilityGranted)
    }

    func test_init_whenAuthorizerNotTrusted_startsNotGranted() {
        sut = makeSUT(initiallyTrusted: false)
        XCTAssertFalse(sut.hasAccessibilityGranted)
    }

    // MARK: recheckPermissions

    func test_recheckPermissions_returnsAndStores_currentAuthorizerState() {
        sut = makeSUT(initiallyTrusted: false)
        authorizer.isTrustedValue = true

        let result = sut.recheckPermissions()

        XCTAssertTrue(result)
        XCTAssertTrue(sut.hasAccessibilityGranted)
    }

    func test_recheckPermissions_publishesUpdatedValue() {
        sut = makeSUT(initiallyTrusted: false)
        authorizer.isTrustedValue = true

        let publishedGranted = expectation(description: "publishes true")
        sut.$hasAccessibilityGranted
            .dropFirst() // ignore the value emitted immediately on subscribe
            .sink { granted in
                XCTAssertTrue(granted)
                publishedGranted.fulfill()
            }
            .store(in: &cancellables)

        _ = sut.recheckPermissions()
        wait(for: [publishedGranted], timeout: 1.0)
    }

    // MARK: requestAccessibilityPermissions

    func test_requestAccessibilityPermissions_whenAlreadyGranted_doesNothing() {
        sut = makeSUT(initiallyTrusted: true)

        sut.requestAccessibilityPermissions()

        XCTAssertEqual(authorizer.requestTrustCallCount, 0)
        XCTAssertEqual(scheduler.scheduleCallCount, 0)
    }

    func test_requestAccessibilityPermissions_whenNotGranted_promptsAndStartsPolling() {
        sut = makeSUT(initiallyTrusted: false)

        sut.requestAccessibilityPermissions()

        XCTAssertEqual(authorizer.requestTrustCallCount, 1)
        XCTAssertEqual(authorizer.lastPromptingUser, true)
        XCTAssertEqual(scheduler.scheduleCallCount, 1)
    }

    // MARK: watchForPermissionChange

    func test_watchForPermissionChange_schedulesOneSecondPoll() {
        sut = makeSUT(initiallyTrusted: false)

        sut.watchForPermissionChange()

        XCTAssertEqual(scheduler.scheduleCallCount, 1)
        XCTAssertEqual(scheduler.lastInterval, 1.0)
    }

    func test_watchForPermissionChange_calledTwice_onlySchedulesOnce() {
        sut = makeSUT(initiallyTrusted: false)

        sut.watchForPermissionChange()
        sut.watchForPermissionChange()

        XCTAssertEqual(scheduler.scheduleCallCount, 1)
    }

    func test_pollTick_whenAuthorizerNowTrusted_updatesPublishedValue() {
        sut = makeSUT(initiallyTrusted: false)
        sut.watchForPermissionChange()

        authorizer.isTrustedValue = true
        scheduler.fireTick()

        XCTAssertTrue(sut.hasAccessibilityGranted)
    }

    func test_pollTick_whenAuthorizerUnchanged_doesNotPublish() {
        sut = makeSUT(initiallyTrusted: false)
        sut.watchForPermissionChange()

        let unexpectedPublish = expectation(description: "should not publish")
        unexpectedPublish.isInverted = true
        sut.$hasAccessibilityGranted
            .dropFirst()
            .sink { _ in unexpectedPublish.fulfill() }
            .store(in: &cancellables)

        scheduler.fireTick() // authorizer still false — no change expected

        wait(for: [unexpectedPublish], timeout: 0.3)
    }

    // MARK: Cleanup

    func test_deinit_invalidatesPollToken() {
        sut = makeSUT(initiallyTrusted: false)
        sut.watchForPermissionChange()

        sut = nil

        XCTAssertEqual(scheduler.token.invalidateCallCount, 1)
    }
}
