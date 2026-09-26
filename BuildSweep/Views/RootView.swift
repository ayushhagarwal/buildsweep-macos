import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView(model: model)
            } else {
                NavigationSplitView {
                    SidebarView(model: model)
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar {
                    ToolbarItemGroup {
                        scanToolbarItem
                        Button {
                            model.selectXcodeRebuildableCaches()
                        } label: {
                            Label("Select Safe Caches", systemImage: "checkmark.circle")
                        }
                        .disabled(model.snapshot.allItems.allSatisfy { $0.kind != .derivedData && $0.kind != .compilerCache })
                        .help("Select only rebuildable Xcode Derived Data and compiler caches.")
                        Menu {
                            ForEach(CleanupPreset.allCases) { preset in
                                Button {
                                    model.prepareCleanup(preset: preset)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(preset.title)
                                        Text(preset.explanation)
                                    }
                                }
                            }
                        } label: {
                            Label("Cleanup Presets", systemImage: "checklist")
                        }
                        .help("Choose a preset to select eligible items and inspect every path before confirmation.")
                        Button {
                            model.prepareCleanup()
                        } label: {
                            Label("Review Cleanup", systemImage: "trash")
                        }
                        .disabled(model.selectedItemIDs.isEmpty)
                        .help("Review \(model.selectedItemIDs.count) selected items")
                    }
                }
            }
        }
        .sheet(isPresented: $model.showingCleanupReview, onDismiss: model.cleanupReviewWasDismissed) {
            if let plan = model.preservedPlan {
                CleanupReviewView(model: model, plan: plan)
                    .buildSweepAppearance()
            }
        }
        .sheet(item: $model.latestCleanupResult) { result in
            CleanupResultView(result: result)
                .buildSweepAppearance()
        }
        .alert("BuildSweep", isPresented: Binding(
            get: { model.appMessage != nil },
            set: { if !$0 { model.appMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.appMessage = nil }
        } message: {
            Text(model.appMessage ?? "")
        }
        .task {
            model.configureMainWindowOpener { openWindow(id: "main") }
        }
        .onChange(of: model.showingCleanupReview) { _, isShowing in
            if isShowing {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .overview: DashboardView(model: model)
        case .history: HistoryView(model: model)
        default: CategoryView(model: model, category: model.selection)
        }
    }

    @ViewBuilder
    private var scanToolbarItem: some View {
        switch model.scanState {
        case .scanning(let completed, let total):
            HStack(spacing: 8) {
                ProgressView(value: Double(completed), total: Double(total))
                    .frame(width: 74)
                Button("Cancel") { model.cancelScan() }
            }
        default:
            Button { model.startScan() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                .help("Scan Xcode storage")
        }
    }
}

private struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                ForEach(StorageCategoryID.allCases.filter { $0 != .history }) { category in
                    Label {
                        Text(category.title)
                    } icon: {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(BuildSweepTheme.categoryForeground(for: category))
                    }
                    .badge(categorySize(category))
                    .tag(category)
                }
            }
            Section {
                Label {
                    Text(StorageCategoryID.history.title)
                } icon: {
                    Image(systemName: StorageCategoryID.history.systemImage)
                        .foregroundStyle(BuildSweepTheme.categoryForeground(for: .history))
                }
                .tag(StorageCategoryID.history)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BuildSweep")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarSafetyCallout()
                .padding(12)
        }
    }

    private func categorySize(_ category: StorageCategoryID) -> String {
        if category == .overview { return "" }
        guard let bytes = model.snapshot.categories[category]?.totalSize, bytes > 0 else { return "" }
        return BuildSweepFormatters.bytes(bytes)
    }
}

private struct SidebarSafetyCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconTile(systemImage: "trash", size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cleanup is free")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Selected items move to Trash and can be restored from Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(emphasized: true)
        .accessibilityElement(children: .combine)
    }
}
