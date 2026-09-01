//
//  FinderBridge.swift
//  FinderCutPaste
//
//  Created by Kyle Y on 2026-08-18.
//

import ApplicationServices

final class FinderBridge {
    static func moveViaFinder(urls: [URL]) -> Bool {
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
    
    // MARK: - Finder AppleScript bridge
    static func selectionURLs() -> [URL]? {
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

    private static func runAppleScript(_ source: String) -> NSAppleEventDescriptor? {
        if let script = NSAppleScript(source: source) {
            var errorDict: NSDictionary?
            let result = script.executeAndReturnError(&errorDict)
            if let error = errorDict {
                NSLog("FinderCutPaste AppleScript error: \(error)")
                return nil
            }
            return result
        }
        return nil
    }
}
