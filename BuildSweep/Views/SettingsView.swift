import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            Form {
                Section("Startup") {
                    Toggle("Launch BuildSweep at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Text("BuildSweep does not schedule periodic cleanup or run a background helper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Authorized folders") {
                    ForEach(model.xcodeAuthorizedRoots) { root in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(root.kind.settingsTitle)
                                Text(root.url.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget", role: .destructive) { Task { await model.forgetRoot(root) } }
                        }
                    }
                    Button(model.xcodeCacheRoot == nil ? "Add Optional Xcode Cache Folder…" : "Reselect Xcode Cache Folder…") {
                        Task { await model.grantXcodeCacheAccess() }
                    }
                }
                Section("AI tool folders") {
                    Text("Scans cache and logs only; chats and skills are never read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(AIToolGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.title)
                                Spacer()
                                if model.hasMissingGrant(in: group) {
                                    Button("Grant…") { Task { await model.grantAIToolGroup(group) } }
                                }
                                if model.hasGranted(group) {
                                    Button("Forget", role: .destructive) { Task { await model.forgetAIToolGroup(group) } }
                                }
                            }
                            ForEach(model.roots(in: group)) { root in
                                Text(root.url.path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                Section("Local data") {
                    Button("Clear Cleanup History", role: .destructive) { Task { await model.clearHistory() } }
                    Text("Bookmarks, preferences, and cleanup history stay on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Privacy", systemImage: "hand.raised") }

            Form {
                Section("Report a Bug") {
                    Link("Email a bug report", destination: mailURL(subject: "BuildSweep Bug Report"))
                    Text("support@ayushdev.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Report a Bug", systemImage: "ant.circle") }

            Form {
                Section("Request a Feature") {
                    Link("Email a feature request", destination: mailURL(subject: "BuildSweep Feature Request"))
                    Text("support@ayushdev.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Request a Feature", systemImage: "lightbulb") }
        }
        .frame(width: 590, height: 560)
        .scenePadding()
        .buildSweepAppearance()
    }

    private func mailURL(subject: String) -> URL {
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        return URL(string: "mailto:support@ayushdev.com?subject=\(encoded)")!
    }
}
