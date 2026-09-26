import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel

    private let displayCategories: [StorageCategoryID] = [.derivedData, .archives, .deviceSupport, .simulators, .cachesAndLogs, .aiTools]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    metrics
                    categoryBreakdown
                    safetySummary
                }
                .padding(28)
                .frame(maxWidth: 1100, alignment: .leading)
            }
        }
        .navigationTitle("Overview")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Xcode storage at a glance")
                    .font(.largeTitle.bold())
                Text(lastScanText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.xcodeIsRunning {
                Label("Xcode is running", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .surfaceCard(cornerRadius: 12)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 14) {
            MetricCard(
                title: "Xcode storage",
                value: BuildSweepFormatters.bytes(model.snapshot.totalSize),
                detail: "Across authorized categories",
                systemImage: "externaldrive"
            )
            MetricCard(
                title: "Estimated reclaimable",
                value: BuildSweepFormatters.bytes(model.snapshot.reclaimableSize),
                detail: "Allocated size; actual free space may differ",
                systemImage: "sparkles",
                emphasized: true,
                tint: BuildSweepTheme.accent
            )
            MetricCard(
                title: "Disk available",
                value: BuildSweepFormatters.bytes(model.availableDiskSpace),
                detail: "For important usage",
                systemImage: "internaldrive",
                tint: BuildSweepTheme.accent
            )
        }
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Storage by category").font(.title2.bold())
            StorageBar(snapshot: model.snapshot, categories: displayCategories)
            legend
            VStack(spacing: 0) {
                ForEach(displayCategories, id: \.self) { category in
                    Button {
                        model.selection = category
                    } label: {
                        CategoryRow(category: category, size: model.snapshot.categories[category]?.totalSize ?? 0)
                    }
                    .buttonStyle(.plain)
                    if category != displayCategories.last { Divider().padding(.leading, 62) }
                }
            }
            .padding(.horizontal, 8)
            .surfaceCard()
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(displayCategories, id: \.self) { category in
                HStack(spacing: 6) {
                    Capsule()
                        .fill(BuildSweepTheme.categoryFill(for: category))
                        .frame(width: 10, height: 6)
                    Text(category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every gigabyte comes with context").font(.title2.bold())
            Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                GridRow {
                    safetyItem(.regenerates)
                    safetyItem(.reviewFirst)
                    safetyItem(.important)
                }
            }
        }
    }

    private func safetyItem(_ risk: StorageRisk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RiskBadge(risk: risk)
            Text(BuildSweepFormatters.bytes(size(for: risk)))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(risk.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .surfaceCard(cornerRadius: 14)
    }

    private func size(for risk: StorageRisk) -> Int64 {
        model.snapshot.allItems.filter { $0.risk == risk }.reduce(0) { $0 + $1.size }
    }

    private var lastScanText: String {
        if case .scanning(let completed, let total) = model.scanState { return "Scanning progressively — \(completed) of \(total) categories" }
        return "Last scan \(BuildSweepFormatters.date(model.snapshot.completedAt))"
    }
}

private struct CategoryRow: View {
    let category: StorageCategoryID
    let size: Int64
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: category.systemImage, tint: BuildSweepTheme.categoryForeground(for: category), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).fontWeight(.semibold)
                Text(categoryDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(BuildSweepFormatters.bytes(size))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(hovering ? BuildSweepTheme.hoverFill : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
    }

    private var categoryDescription: String {
        switch category {
        case .derivedData: "Build intermediates and indexes"
        case .archives: "Signed build archives and dSYMs"
        case .deviceSupport: "Symbols for connected OS versions"
        case .simulators: "Devices and installed runtimes"
        case .cachesAndLogs: "Known Xcode caches, documentation, and logs"
        case .aiTools: "Cursor, Codex, and Claude caches and logs"
        default: ""
        }
    }
}

private struct StorageBar: View {
    let snapshot: ScanSnapshot
    let categories: [StorageCategoryID]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(categories, id: \.self) { category in
                    let size = snapshot.categories[category]?.totalSize ?? 0
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(BuildSweepTheme.categoryFill(for: category))
                        .frame(width: appeared ? max(size > 0 ? 8 : 2, geometry.size.width * ratio(size)) : 2)
                        .help("\(category.title): \(BuildSweepFormatters.bytes(size))")
                }
            }
        }
        .frame(height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("Storage segmented by category")
        .onAppear {
            withAnimation(BuildSweepTheme.animation(reduceMotion, .spring(response: 0.7, dampingFraction: 0.86))) {
                appeared = true
            }
        }
    }

    private func ratio(_ size: Int64) -> CGFloat {
        guard snapshot.totalSize > 0 else { return 0 }
        return CGFloat(Double(size) / Double(snapshot.totalSize))
    }
}
