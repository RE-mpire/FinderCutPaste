import SwiftUI

struct PermissionStatusView: View {
    @ObservedObject var manager = PermissionManager.shared

    var body: some View {
        let isGranted = manager.hasAccessibilityGranted

        VStack(alignment: .leading, spacing: 12) {
            statusHeader(isGranted: isGranted)

            if isGranted {
                grantedContent
            } else {
                deniedContent
            }

            Button("Refresh Status") {
                manager.recheckPermissions()
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            manager.recheckPermissions()
        }
    }

    private func statusHeader(isGranted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isGranted ? .green : .orange)
            Text(isGranted ? "Ready to Use" : "Permission Needed")
                .font(.headline)
        }
    }

    private var grantedContent: some View {
        Text("⌘X and ⌘V will move files in Finder.")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }

    private var deniedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This app needs Accessibility access to detect ⌘X and ⌘V in Finder.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Open System Settings → Privacy & Security → Accessibility, then enable this app. It may already be listed — try toggling it off and back on if it doesn't seem to take effect.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
//                Button("Open Settings") {
//                    manager.openAccessibilitySettings()
//                }
//                .buttonStyle(.bordered)

                Button("Request Permission") {
                    manager.requestAccessibilityPermissions()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
    }
}

#Preview("Granted") {
    let manager = PermissionManager.shared
    return PermissionStatusView(manager: manager)
}
