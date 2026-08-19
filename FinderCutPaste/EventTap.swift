//
//  EventTap.swift
//  FinderCutPaste
//
//  Created by Kyle Y on 2026-08-18.
//
import ApplicationServices
import AppKit

/// Installs a CGEvent tap that intercepts Cmd+X / Cmd+V in Finder so cut/paste
/// can be redirected to move-on-paste semantics instead of the default copy/paste.
final class EventTap {

    // MARK: - Key codes

    /// macOS virtual key codes (US keyboard layout).
    private enum KeyCode {
        static let x: Int64 = 7
        static let v: Int64 = 9
    }

    // MARK: - State

    private var markedURLs: [URL] = []
    private var markedChangeCount: Int = 0

    private var tap: CFMachPort?
    private var runSource: CFRunLoopSource?

    // MARK: - Install / remove
    private func installTap() {
        guard tap == nil else { return } // already installed
        guard let tap = createTap() else { return }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            NSLog("FinderCutPaste: failed to create run loop source for event tap")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runSource = source

        NSLog("FinderCutPaste: event tap installed successfully")
    }
    
    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let eventTap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return eventTap.handle(type: type, event: event)
    }
    
    private func createTap() -> CFMachPort? {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        if tap == nil {
            NSLog("FinderCutPaste: failed to create event tap (Accessibility permission must be granted)")
        }

        return tap
    }

    func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let runSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runSource, .commonModes)
        }

        tap = nil
        runSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableTapIfNeeded()
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, shouldIntercept(event) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == KeyCode.x {
            cutAsync()
            return nil
        } else if keyCode == KeyCode.v {
            return handlePaste(event: event)
        }
        return Unmanaged.passUnretained(event)
    }
    
    private func reenableTapIfNeeded() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Whether this key event is a candidate for our Cmd+X/Cmd+V handling:
    /// Cmd held alone, Finder is frontmost, and we're not inside a text field.
    private func shouldIntercept(_ event: CGEvent) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let flags = event.flags
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate)
        else {
            return false
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return false
        }

        return !isEditingText()
    }

    private func handlePaste(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !markedURLs.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        guard NSPasteboard.general.changeCount == markedChangeCount else {
            clearMarks()
            return Unmanaged.passUnretained(event)
        }

        pasteAsync()
        return nil
    }
    
    private func isEditingText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                           &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let element = focused as! AXUIElement
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else { return false }
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"].contains(role)
    }
    
    private func clearMarks() {
        guard !markedURLs.isEmpty else { return }
        markedURLs = []
        markedChangeCount = 0
    }
}
