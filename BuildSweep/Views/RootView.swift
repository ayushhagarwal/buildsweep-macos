import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

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
        .sheet(isPresented: $model.showingCleanupReview) {
            if let plan = model.preservedPlan {
                CleanupReviewView(model: model, plan: plan)
                    .buildSweepAppearance()
            }
        }
        .sheet(isPresented: $model.showingPaywall) {
            PaywallView(model: model)
                .buildSweepAppearance()
        }
        .sheet(item: $model.latestCleanupResult) { result in
            CleanupResultView(model: model, result: result)
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
            SidebarProCallout(model: model)
                .padding(12)
        }
    }

    private func categorySize(_ category: StorageCategoryID) -> String {
        if category == .overview { return "" }
        guard let bytes = model.snapshot.categories[category]?.totalSize, bytes > 0 else { return "" }
        return BuildSweepFormatters.bytes(bytes)
    }
}

private struct SidebarProCallout: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                IconTile(
                    systemImage: model.isPro ? "checkmark.seal.fill" : "infinity.circle.fill",
                    size: 32
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.isPro {
                Button {
                    model.showingPaywall = true
                } label: {
                    Text("View BuildSweep Pro")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(emphasized: true)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if model.isPro { return "BuildSweep Pro unlocked" }
        if model.freeCleanupConsumed { return "Unlock unlimited cleanup" }
        return "\(model.remainingFreeCleanups) of \(FreeCleanupPolicy.limit) free cleanups left"
    }

    private var detail: String {
        if model.isPro { return "Unlimited cleanup on this Apple ID." }
        return "Scans stay free. Pro is one lifetime purchase."
    }
}

