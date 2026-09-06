import AppKit
import SwiftUI

struct MenuBarStatusView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading) {
            Text("Xcode storage: \(BuildSweepFormatters.bytes(model.snapshot.totalSize))")
            Text("Reclaimable: \(BuildSweepFormatters.bytes(model.snapshot.reclaimableSize))")
            Text(statusText).foregroundStyle(.secondary)
            Divider()
            Button("Rescan") { model.startScan() }.disabled(model.needsOnboarding)
            Button("Open BuildSweep") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink { Text("Settings…") }
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if model.freeCleanupConsumed && !model.isPro {
                Divider()
                Button("Unlock Pro") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    model.showingPaywall = true
                }
            }
            Divider()
            Button("Quit BuildSweep") { NSApplication.shared.terminate(nil) }
        }
    }

    private var statusText: String {
        switch model.scanState {
        case .scanning(let completed, let total): "Scanning \(completed)/\(total)"
        case .complete: "Scanned \(BuildSweepFormatters.date(model.snapshot.completedAt))"
        case .failed: "Scan needs attention"
        case .idle: "Not scanned yet"
        }
    }
}

