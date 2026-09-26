import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var showingStorageMap = false

    private let displayCategories: [StorageCategoryID] = [.derivedData, .archives, .deviceSupport, .simulators, .cachesAndLogs, .aiTools, .developerCaches]

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
        .sheet(isPresented: $showingStorageMap) {
            if let root = model.developerRoot {
                DeveloperStorageMapView(root: root.url)
                    .frame(minWidth: 780, minHeight: 560)
                    .buildSweepAppearance()
            }
        }
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
            if model.developerRoot != nil {
                Button {
                    showingStorageMap = true
                } label: {
                    Label("Storage Map", systemImage: "square.grid.3x3.fill")
                }
                .help("Explore storage inside the authorized Library/Developer folder. Read-only.")
            }
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
                        CategoryRow(category: category, snapshot: model.snapshot.categories[category])
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
        guard let completedAt = model.snapshot.completedAt else { return "No completed scan yet" }
        return "Last scan \(completedAt.formatted(.relative(presentation: .named))) · \(BuildSweepFormatters.date(completedAt))"
    }
}

private struct DeveloperStorageMapView: View {
    private let root: URL
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL
    @State private var currentTitle: String
    @State private var children: [StorageChildSummary] = []
    @State private var selected: StorageChildSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var totalCount = 0

    init(root: URL) {
        self.root = root
        _currentURL = State(initialValue: root)
        _currentTitle = State(initialValue: "Developer")
    }

    private var canGoBack: Bool { currentURL != root }
    private var totalSize: Int64 { children.reduce(0) { $0 + ($1.size ?? 0) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer storage map").font(.largeTitle.bold())
                    Text("\(currentTitle) · \(BuildSweepFormatters.bytes(totalSize)) allocated · \(totalCount) items")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(20)

            HStack(spacing: 8) {
                Button {
                    currentURL = root
                    currentTitle = "Developer"
                    selected = nil
                } label: {
                    Label("Developer", systemImage: "house")
                }
                .buttonStyle(.link)
                if canGoBack {
                    Text("/").foregroundStyle(.tertiary)
                    Text(currentURL.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Parent Folder") {
                        currentURL = currentURL.deletingLastPathComponent()
                        currentTitle = currentURL.lastPathComponent
                        selected = nil
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Group {
                if isLoading {
                    ProgressView("Measuring folder sizes…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn’t read this folder", systemImage: "folder.badge.questionmark", description: Text(errorMessage))
                } else if children.isEmpty {
                    ContentUnavailableView("No items in this folder", systemImage: "folder", description: Text("There is no storage to map at this level."))
                } else {
                    HStack(spacing: 0) {
                        TreemapTileView(children: children, onSelect: { selected = $0 })
                            .padding(12)
                        if let selected {
                            mapItemInspector(selected)
                                .frame(width: 250)
                                .padding(.trailing, 16)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Label("Folders can be opened for deeper inspection", systemImage: "folder")
                Spacer()
                Text("Read-only · allocated-size estimates · no file contents read")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(14)
            .background(.bar)
        }
        .task(id: currentURL) {
            isLoading = true
            errorMessage = nil
            do {
                let result = try await DirectorySizer().inspectImmediateChildren(of: currentURL, limit: 200)
                children = result.children
                totalCount = result.totalCount
            } catch is CancellationError {
                return
            } catch {
                children = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func mapItemInspector(_ item: StorageChildSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(item.isDirectory ? "Folder" : "File", systemImage: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.name).font(.title3.bold()).textSelection(.enabled)
            Text(item.url.path(percentEncoded: false))
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            LabeledContent("Allocated", value: item.size.map(BuildSweepFormatters.bytes) ?? "Unavailable")
            LabeledContent("Modified", value: item.modifiedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unknown")
            if item.isSymbolicLink {
                Label("Symbolic links are not traversed.", systemImage: "link")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDirectory && !item.isSymbolicLink {
                Button("Open Folder") {
                    currentURL = item.url
                    currentTitle = item.name
                    selected = nil
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                .buttonStyle(.link)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .surfaceCard(cornerRadius: 14)
    }
}

private struct TreemapTileView: View {
    let children: [StorageChildSummary]
    let onSelect: (StorageChildSummary) -> Void

    var body: some View {
        GeometryReader { geometry in
            let placements = TreemapPartition.layout(children, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                ForEach(children) { child in
                    if let rect = placements[child.id] {
                        Button { onSelect(child) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                                if rect.width > 86 && rect.height > 38 {
                                    Text(child.name).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(child.size.map(BuildSweepFormatters.bytes) ?? "Unavailable")
                                        .font(.caption2.monospacedDigit()).opacity(0.76)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(8)
                            .background(child.isDirectory ? BuildSweepTheme.accentSoft : BuildSweepTheme.categoryFill(for: .developerCaches), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.75), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(0, rect.width - 3), height: max(0, rect.height - 3))
                        .position(x: rect.midX, y: rect.midY)
                        .help("\(child.name) · \(child.size.map(BuildSweepFormatters.bytes) ?? "size unavailable")")
                    }
                }
            }
        }
        .accessibilityLabel("Read-only treemap of folder usage")
    }
}

private enum TreemapPartition {
    static func layout(_ items: [StorageChildSummary], in rect: CGRect) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        partition(items.sorted { ($0.size ?? 0) > ($1.size ?? 0) }, in: rect, into: &result)
        return result
    }

    private static func partition(_ items: [StorageChildSummary], in rect: CGRect, into result: inout [String: CGRect]) {
        guard !items.isEmpty else { return }
        guard items.count > 1 else {
            result[items[0].id] = rect
            return
        }
        let weights = items.map { max(1, $0.size ?? 0) }
        let total = Double(weights.reduce(0, +))
        let target = total / 2
        var accumulated = 0.0
        var splitIndex = 1
        for index in 0..<(items.count - 1) {
            accumulated += Double(weights[index])
            splitIndex = index + 1
            if accumulated >= target { break }
        }
        let firstWeight = weights[..<splitIndex].reduce(0, +)
        let fraction = min(0.92, max(0.08, Double(firstWeight) / total))
        if rect.width >= rect.height {
            let width = rect.width * fraction
            partition(Array(items[..<splitIndex]), in: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height), into: &result)
            partition(Array(items[splitIndex...]), in: CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height), into: &result)
        } else {
            let height = rect.height * fraction
            partition(Array(items[..<splitIndex]), in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height), into: &result)
            partition(Array(items[splitIndex...]), in: CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height), into: &result)
        }
    }
}

private struct CategoryRow: View {
    let category: StorageCategoryID
    let snapshot: StorageCategorySnapshot?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemImage: category.systemImage, tint: BuildSweepTheme.categoryForeground(for: category), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).fontWeight(.semibold)
                Text(categoryDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
                if snapshot?.status == .failed {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .help(snapshot?.warnings.joined(separator: "\n") ?? "This category could not be scanned.")
                } else if snapshot?.status == .partial {
                    Label("Partial", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .help(snapshot?.warnings.joined(separator: "\n") ?? "This category was only partially scanned.")
                }
                Text(BuildSweepFormatters.bytes(snapshot?.totalSize ?? 0))
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
        case .developerCaches: "Separately approved Swift, Apple, and JavaScript package caches"
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
