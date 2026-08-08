import SwiftUI
struct PermissionStatusView: View {
    @ObservedObject var manager = FinderCutPasteStandalone.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: manager.isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(manager.isAccessibilityGranted ? .green : .orange)
                Text(manager.isAccessibilityGranted ? "Ready to use" : "Permission needed")
                    .font(.headline)
            }
            if manager.isAccessibilityGranted {
                Text("⌘X and ⌘V will move files in Finder.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This app needs Accessibility access to detect ⌘X and ⌘V in Finder.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Open System Settings → Privacy & Security → Accessibility, then enable this app. It may already be listed — try toggling it off and back on if it doesn't seem to take effect.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Button("Retry Permission Request") {
                            manager.retryPermissionRequest()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Button("Refresh status") {
                manager.refreshPermissionStatus()
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            manager.refreshPermissionStatus()
        }
    }
}
