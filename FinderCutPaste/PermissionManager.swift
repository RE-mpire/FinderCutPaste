//
//  PermissionManager.swift
//  FinderCutPaste
//
//  Created by Kyle Y on 2026-08-14.
//

import ApplicationServices
import Combine

final class PermissionManager: ObservableObject {
    @Published private(set) var hasAccessibilityGranted: Bool = AXIsProcessTrusted()
    
    // MARK: - State
    private var permissionPollTimer: Timer?
    
    deinit {
        stopTimer()
    }
    
    func recheckPermissions() -> Bool {
        hasAccessibilityGranted = AXIsProcessTrusted()
        return hasAccessibilityGranted
    }
    
    func requestAccessibilityPermissions() {
        guard !hasAccessibilityGranted else {
            NSLog("FinderCutPaste: Accessibility permissions already granted")
            return
        }
        
        // Create permission prompt
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
        
        NSLog("FinderCutPaste: Accessibility permissions requested — waiting for user to enable it in System Settings")
        watchForPermissionChange()
    }
    
    func watchForPermissionChange() {
        guard permissionPollTimer == nil else {
            NSLog("FinderCutPaste: Permission timer already running")
            return
        }
        
        // Create timer to check AXIsProcessTrusted() every second, once granted self terminate timer
        permissionPollTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let granted = AXIsProcessTrusted()

            if granted != self.hasAccessibilityGranted {
                self.hasAccessibilityGranted = granted
            }
        }
    }
    
    private func stopTimer() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
}
