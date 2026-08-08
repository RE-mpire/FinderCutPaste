/*
 FinderCutPaste.swift
 Minimal standalone implementation of ⌘X (cut) and ⌘V (move) for Finder.

 Notes:
 - Requires Accessibility (System Settings → Privacy & Security → Accessibility).
 - Requires Apple Events (NSAppleEventsUsageDescription in Info.plist) to query Finder.
 - Put this file into a macOS App target; the service starts when the app runs.
*/

import Cocoa
import ApplicationServices
import AppKit
import Combine

final class FinderCutPasteStandalone: ObservableObject {
    static let shared = FinderCutPasteStandalone()

    private init() {}

    // MARK: - Published state for UI
    @Published private(set) var isAccessibilityGranted: Bool = AXIsProcessTrusted()

    // MARK: - State
    private var markedURLs: [URL] = []
    private var markedChangeCount: Int = 0
    private var tap: CFMachPort?
    private var permissionPollTimer: Timer?

    // ANSI virtual key codes used by macOS
    private enum Key {
        static let x: Int64 = 7
        static let v: Int64 = 9
    }

    // MARK: - Public
    func start() {
        requestAccessibilityPermissionThenStart()
    }

    func stop() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runSource, .commonModes)
            }
        }
        tap = nil
    }

    // MARK: - Permission handling
    private func requestAccessibilityPermissionThenStart() {
        if AXIsProcessTrusted() {
            isAccessibilityGranted = true
            installTap()
            return
        }

        isAccessibilityGranted = false

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)

        NSLog("FinderCutPasteStandalone: Accessibility not granted yet — waiting for user to enable it in System Settings")

        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let granted = AXIsProcessTrusted()
            if self.isAccessibilityGranted != granted {
                self.isAccessibilityGranted = granted
            }
            if granted {
                timer.invalidate()
                self.permissionPollTimer = nil
                NSLog("FinderCutPasteStandalone: Accessibility granted — starting event tap")
                self.installTap()
            }
        }
    }

    // Call this if the user manually flips the toggle off in System Settings while the app is running,
    // or to let the UI trigger a re-check on demand.
    func refreshPermissionStatus() {
        let granted = AXIsProcessTrusted()
        if isAccessibilityGranted != granted {
            isAccessibilityGranted = granted
            if granted {
                installTap()
            } else {
                stop()
            }
        }
    }

    // Re-triggers the AX permission prompt. Useful if the user dismissed it,
    // or if the system dialog didn't appear the first time.
    func retryPermissionRequest() {
        let alreadyTrusted = AXIsProcessTrusted()
        if alreadyTrusted {
            isAccessibilityGranted = true
            installTap()
            return
        }

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        let granted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = granted

        NSLog("FinderCutPasteStandalone: retryPermissionRequest — prompt triggered, granted=\(granted)")

        // Make sure polling is (re)running in case the user grants it after this call returns.
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let granted = AXIsProcessTrusted()
            if self.isAccessibilityGranted != granted {
                self.isAccessibilityGranted = granted
            }
            if granted {
                timer.invalidate()
                self.permissionPollTimer = nil
                self.installTap()
            }
        }
    }
    
    // MARK: - Event tap
    private func installTap() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissionThenStart()
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let ref = Unmanaged<FinderCutPasteStandalone>.fromOpaque(userInfo).takeUnretainedValue()
                return ref.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("FinderCutPasteStandalone: failed to create event tap (check: App Sandbox must be OFF, and Accessibility permission must be granted)")
            return
        }
        self.tap = tap
        if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("FinderCutPasteStandalone: event tap installed successfully")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              (keyCode == Key.x || keyCode == Key.v),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              !isEditingText()
        else {
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case Key.x:
            cutAsync()
            return nil
        case Key.v:
            if !markedURLs.isEmpty {
                if NSPasteboard.general.changeCount == markedChangeCount {
                    pasteAsync()
                    return nil
                } else {
                    clearMarks()
                }
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Cut
    private func cutAsync() {
        DispatchQueue.main.async { [weak self] in
            guard let urls = Self.selectionURLs(), !urls.isEmpty else {
                self?.clearMarks()
                return
            }
            self?.applyCut(urls)
        }
    }

    private func applyCut(_ urls: [URL]) {
        markedURLs = urls
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        markedChangeCount = pb.changeCount
        NSLog("FinderCutPasteStandalone: cut \(urls.count) item(s)")
    }

    private func clearMarks() {
        guard !markedURLs.isEmpty else { return }
        markedURLs = []
        markedChangeCount = 0
    }
    
    private static func moveViaFinder(urls: [URL]) -> Bool {
        // Build an AppleScript list literal of POSIX paths, e.g.:
        // {"/Users/me/a.txt", "/Users/me/b.txt"}
        let fileList = urls
            .map { "(POSIX file \"\($0.path.replacingOccurrences(of: "\"", with: "\\\""))\")" }
            .joined(separator: ", ")

        let script = """
        tell application "Finder"
            set theItems to {\(fileList)}
            set targetFolder to insertion location
            move theItems to targetFolder
        end tell
        """
        return runAppleScript(script) != nil
    }

    // MARK: - Paste (move)
    private func pasteAsync() {
        let urls = markedURLs
        guard !urls.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = Self.moveViaFinder(urls: urls)
            DispatchQueue.main.async {
                NSLog("FinderCutPasteStandalone: Finder move \(success ? "succeeded" : "failed")")
                self?.clearMarks()
            }
        }
    }

    // MARK: - Finder AppleScript bridge
    private static func selectionURLs() -> [URL]? {
        let script = """
        tell application "Finder"
            set out to ""
            repeat with f in (get selection)
                set out to out & (POSIX path of (f as alias)) & linefeed
            end repeat
            return out
        end tell
        """
        guard let desc = runAppleScript(script), let output = desc.stringValue else { return nil }
        let lines = output.split(whereSeparator: \.isNewline).map { String($0) }
        return lines.map { URL(fileURLWithPath: $0) }
    }

    private static func insertionLocationPath() -> String? {
        let script = """
        tell application "Finder"
            return POSIX path of (insertion location as alias)
        end tell
        """
        guard let desc = runAppleScript(script), let out = desc.stringValue else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        if let script = NSAppleScript(source: source) {
            var errorDict: NSDictionary?
            let result = script.executeAndReturnError(&errorDict)
            if let error = errorDict {
                NSLog("FinderCutPasteStandalone AppleScript error: \(error)")
                return nil
            }
            return result
        }
        return nil
    }

    // MARK: - Helpers
    private static func uniqueDestination(for name: String, in dir: URL, fm: FileManager) -> URL {
        var candidate = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            let next = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(next)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
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
}
