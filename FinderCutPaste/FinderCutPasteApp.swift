import SwiftUI

@main
struct FinderCutPastePoCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            PermissionStatusView()
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FinderCutPasteStandalone.shared.start()
        NSLog("FinderCutPastePoC: started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        FinderCutPasteStandalone.shared.stop()
        NSLog("FinderCutPastePoC: stopping")
    }
}
