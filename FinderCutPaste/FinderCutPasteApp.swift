import SwiftUI
import Combine

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
    var pm = PermissionManager.shared
    var tap = EventTap()
    
    private var permissionCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissionCancellable = pm.$hasAccessibilityGranted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.tap.installTap()
                    NSLog("FinderCutPaste: started")
                } else {
                    self.tap.removeTap()
                    NSLog("FinderCutPaste: Accessibility not granted — tap removed")
                }
            }
 
        if !pm.hasAccessibilityGranted {
            pm.requestAccessibilityPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.removeTap()
    }
}
