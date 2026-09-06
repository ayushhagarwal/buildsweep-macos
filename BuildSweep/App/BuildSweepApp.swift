import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct BuildSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("BuildSweep", id: "main") {
            RootView(model: model)
                .buildSweepAppearance()
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandMenu("Storage") {
                Button("Scan Xcode Storage") { model.startScan() }
                    .keyboardShortcut("r")
                    .disabled(model.needsOnboarding)
                Button("Review Selected Cleanup") { model.prepareCleanup() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .disabled(model.selectedItemIDs.isEmpty)
            }
        }

        MenuBarExtra("BuildSweep", systemImage: "externaldrive.badge.checkmark") {
            MenuBarStatusView(model: model)
        }

        Settings {
            SettingsView(model: model)
                .buildSweepAppearance()
        }
    }
}

