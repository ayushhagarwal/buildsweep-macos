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
                            ForEach(AIToolDataScope.allCases) { scope in
                                Toggle("\(scope.title) cleanup", isOn: Binding(
                                    get: { model.isAIToolScopeEnabled(scope, for: group) },
                                    set: { model.setAIToolScopeEnabled($0, scope: scope, for: group) }
                                ))
                                Text("Included locations: \(scopeDescription(scope, for: group))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section("AI tool log retention") {
                    Picker("Keep recent logs out of cleanup", selection: Binding(
                        get: { model.aiLogRetentionDays },
                        set: { model.setAILogRetentionDays($0) }
                    )) {
                        Text("Off").tag(0)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    Text("A log folder stays inspection-only if any file in it was modified within this period. BuildSweep checks dates and sizes, not log contents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private func scopeDescription(_ scope: AIToolDataScope, for group: AIToolGroup) -> String {
        switch (group, scope) {
        case (.cursor, .cache): "Cache, CachedData, CachedExtensionVSIXs, Code Cache, GPUCache, DawnGraphiteCache, DawnWebGPUCache, blob_storage"
        case (.cursor, .logs): "Crashpad, logs, ai-tracking, debug-logs"
        case (.codex, .cache): "cache, .tmp, and the granted Codex system cache folders"
        case (.codex, .logs): "No separate Codex log folders are currently scanned"
        case (.claude, .cache): "cache, Cache, CachedData, GPUCache, and the granted Claude system cache"
        case (.claude, .logs): "logs"
        }
    }
}
