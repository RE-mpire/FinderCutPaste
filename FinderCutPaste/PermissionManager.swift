//
//  PermissionManager.swift
//  FinderCutPaste
//
//  Created by Kyle Y on 2026-08-14.
//
import ApplicationServices
import AppKit
import Combine

protocol AccessibilityAuthorizing {
    func isTrusted() -> Bool
    @discardableResult
    func requestTrust(promptingUser: Bool) -> Bool
}

struct SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestTrust(promptingUser: Bool) -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: promptingUser
        ]
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// A handle to a scheduled repeating task, so callers don't need to know it's a `Timer`.
protocol TimerToken {
    func invalidate()
}

extension Timer: TimerToken {}

/// Wraps `Timer` scheduling so tests can trigger polls manually instead of waiting on real time.
protocol TimerScheduling {
    func scheduleRepeating(interval: TimeInterval, handler: @escaping () -> Void) -> TimerToken
}

struct FoundationTimerScheduler: TimerScheduling {
    func scheduleRepeating(interval: TimeInterval, handler: @escaping () -> Void) -> TimerToken {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in handler() }
    }
}

// MARK: - PermissionManager

final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published private(set) var hasAccessibilityGranted: Bool

    // MARK: - Dependencies

    private let authorizer: AccessibilityAuthorizing
    private let scheduler: TimerScheduling

    // MARK: - State

    private var permissionPollToken: TimerToken?

    init(
        authorizer: AccessibilityAuthorizing = SystemAccessibilityAuthorizer(),
        scheduler: TimerScheduling = FoundationTimerScheduler()
    ) {
        self.authorizer = authorizer
        self.scheduler = scheduler
        self.hasAccessibilityGranted = authorizer.isTrusted()
    }

    deinit {
        stopTimer()
    }

    @discardableResult
    func recheckPermissions() -> Bool {
        hasAccessibilityGranted = authorizer.isTrusted()
        return hasAccessibilityGranted
    }

    func requestAccessibilityPermissions() {
        guard !hasAccessibilityGranted else {
            NSLog("FinderCutPaste: Accessibility permissions already granted")
            return
        }

        authorizer.requestTrust(promptingUser: true)

        NSLog("FinderCutPaste: Accessibility permissions requested — waiting for user to enable it in System Settings")
        watchForPermissionChange()
    }
    

    func watchForPermissionChange() {
        guard permissionPollToken == nil else {
            NSLog("FinderCutPaste: Permission timer already running")
            return
        }

        // Poll AXIsProcessTrusted() every second; self-updates once the user grants access.
        permissionPollToken = scheduler.scheduleRepeating(interval: 1.0) { [weak self] in
            guard let self else { return }
            let granted = self.authorizer.isTrusted()
            if granted != self.hasAccessibilityGranted {
                self.hasAccessibilityGranted = granted
            }
        }
    }
    
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    private func stopTimer() {
        permissionPollToken?.invalidate()
        permissionPollToken = nil
    }
}
