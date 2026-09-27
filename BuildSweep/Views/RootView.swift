import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    let contentSize: CGSize
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView(model: model)
            } else {
                // Bound each hosted pane independently: intrinsic scroll-content sizing
                // can otherwise make NSSplitView taller than its window.
                NavigationSplitView {
                    GeometryReader { pane in
                        SidebarView(model: model)
                            .frame(width: pane.size.width, height: pane.size.height, alignment: .topLeading)
                    }
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } detail: {
                    GeometryReader { pane in
                        detail
                            .frame(width: pane.size.width, height: pane.size.height, alignment: .topLeading)
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar {
                    if model.selection != .overview {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                model.selection = .overview
                                model.searchText = ""
                            } label: {
                                Label("Back to Overview", systemImage: "chevron.left")
                            }
                            .help("Back to Overview")
                        }
                    }
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
        .sheet(isPresented: Binding(
            get: { model.showingCleanupReview || model.latestCleanupResult != nil },
            set: { presented in
                if !presented {
                    model.cancelCleanupReview()
                    model.latestCleanupResult = nil
                }
            }
        ), onDismiss: model.cleanupReviewWasDismissed) {
            Group {
                if let result = model.latestCleanupResult {
                    CleanupResultView(result: result)
                } else if let plan = model.preservedPlan {
                    CleanupReviewView(model: model, plan: plan)
                }
            }
            .frame(
                width: min(760, max(640, contentSize.width - 80)),
                height: min(600, max(480, contentSize.height - 24))
            )
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
            model.configureMainWindowOpener {
                if let existingWindow = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                    existingWindow.deminiaturize(nil)
                    existingWindow.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            Group {
                switch model.selection {
                case .overview: DashboardView(model: model)
                case .history: HistoryView(model: model)
                default: CategoryView(model: model, category: model.selection)
                }
            }
            .id(model.selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            CleanupActionBar(model: model)
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

private struct CleanupActionBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.selectedItems.isEmpty {
                Label(
                    "To free space, open a category and select items. Review them before confirming cleanup.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Label(
                    "\(model.selectedItems.count) selected · \(BuildSweepFormatters.bytes(model.selectedSize)) estimated",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Button("Clear Selection") {
                    model.selectedItemIDs.removeAll()
                }
                Button {
                    model.prepareCleanup()
                } label: {
                    Label("Review Cleanup", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .help("Review selected items and their effects before moving anything to Trash.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxHeight: .infinity)
            .clipped()

            SidebarSafetyCallout()
                .padding(12)
        }
        .navigationTitle("BuildSweep")
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
