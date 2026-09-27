import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var showingStorageMap = false

    private let displayCategories: [StorageCategoryID] = [.derivedData, .archives, .deviceSupport, .simulators, .cachesAndLogs, .aiTools, .developerCaches]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    metrics
                    categoryBreakdown
                    safetySummary
                }
                .padding(28)
                .frame(maxWidth: 1100, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .navigationTitle("Overview")
        .sheet(isPresented: $showingStorageMap) {
            if let root = model.developerRoot {
                DeveloperStorageMapView(root: root.url)
                    .frame(width: 940, height: 640)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
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
        return "Last scan \(completedAt.formatted(.relative(presentation: .named)))"
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

    private var rankedChildren: [StorageChildSummary] {
        children.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    // Tiny and unmeasured entries remain accessible in the list without
    // distorting the area of the map or rendering unusable slivers.
    private var mappedChildren: [StorageChildSummary] {
        Array(rankedChildren.filter { Double($0.size ?? 0) >= Double(max(1, totalSize)) * 0.01 && ($0.size ?? 0) > 0 }.prefix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("STORAGE EXPLORER", systemImage: "square.grid.2x2")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    Text(currentTitle).font(.system(size: 26, weight: .bold))
                    Text("See what’s taking space. Select a folder to explore.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(BuildSweepFormatters.bytes(totalSize))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("allocated in this view").font(.caption).foregroundStyle(.secondary)
                }
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Close storage explorer").keyboardShortcut(.cancelAction)
                    .padding(.leading, 16)
            }
            .padding(24)

            HStack(spacing: 10) {
                Button {
                    currentURL = root
                    currentTitle = "Developer"
                    selected = nil
                } label: { Label("Developer", systemImage: "house") }
                .buttonStyle(.plain).foregroundStyle(BuildSweepTheme.accent)
                if canGoBack {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(currentURL.path.replacingOccurrences(of: root.path + "/", with: ""))
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
                Spacer()
                if canGoBack {
                    Button {
                        currentURL = currentURL.deletingLastPathComponent()
                        currentTitle = currentURL == root ? "Developer" : currentURL.lastPathComponent
                        selected = nil
                    } label: { Label("Back", systemImage: "arrow.up") }
                    .buttonStyle(.borderless)
                }
                Text("\(children.count) of \(totalCount) items").foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 24).padding(.bottom, 16)

            Group {
                if isLoading {
                    ProgressView("Measuring storage…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Couldn’t read this folder", systemImage: "folder.badge.questionmark", description: Text(errorMessage))
                } else if children.isEmpty {
                    ContentUnavailableView("This folder is empty", systemImage: "folder", description: Text("Go back to explore another folder."))
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            TreemapTileView(children: mappedChildren, totalSize: totalSize, selectedID: selected?.id, onSelect: { selected = $0 })
                            Text("Largest items mapped · all measured items are in the list")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("CONTENTS").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                                Spacer()
                                Text("Largest first").font(.caption)
                            }.foregroundStyle(.secondary)
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(Array(rankedChildren.enumerated()), id: \.element.id) { index, item in
                                        Button { selected = item } label: {
                                            HStack(spacing: 10) {
                                                RoundedRectangle(cornerRadius: 3).fill(mapColor(index)).frame(width: 7, height: 28)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                                                    Text(mapSize(item.size))
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer(minLength: 2)
                                                Image(systemName: item.isDirectory ? "folder" : "doc").foregroundStyle(.secondary)
                                            }
                                            .padding(10)
                                            .background(selected?.id == item.id ? BuildSweepTheme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                            .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            if let selected {
                                Divider()
                                mapItemInspector(selected)
                            } else {
                                Label("Select an item to see its details.", systemImage: "cursorarrow.click")
                                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                            }
                        }
                        .frame(width: 270)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24).padding(.bottom, 20)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Read-only inspection")
                Spacer()
                Text("Allocated sizes are estimates. No file contents are read.")
                if totalCount > children.count {
                    Image(systemName: "info.circle").help("Only the first 200 items alphabetically are measured. Totals cover those items only.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.white.opacity(0.7))
            .overlay(alignment: .top) { Divider() }
        }
        .background(BuildSweepTheme.canvas)
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

    private func mapItemInspector(_ item: StorageChildSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name).font(.headline).lineLimit(2).textSelection(.enabled)
            Text(item.url.path(percentEncoded: false))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled).help(item.url.path)
            Text("Modified \(item.modifiedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "date unavailable")")
                .font(.caption).foregroundStyle(.secondary)
            if item.isSymbolicLink {
                Label("Symbolic link · not followed", systemImage: "link").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if item.isDirectory && !item.isSymbolicLink {
                    Button("Explore Folder") {
                        currentURL = item.url
                        currentTitle = item.name
                        selected = nil
                    }.buttonStyle(.borderedProminent)
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }.help("Reveal in Finder").accessibilityLabel("Reveal in Finder")
            }
        }
        .padding(.top, 4)
    }
}

private func mapSize(_ size: Int64?) -> String {
    guard let size else { return "Size unavailable" }
    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}

private func mapColor(_ index: Int) -> Color {
    let palette: [Color] = [Color(red: 0.20, green: 0.43, blue: 0.87), Color(red: 0.38, green: 0.33, blue: 0.78), Color(red: 0.12, green: 0.57, blue: 0.62), Color(red: 0.77, green: 0.40, blue: 0.23), Color(red: 0.60, green: 0.34, blue: 0.64), Color(red: 0.30, green: 0.52, blue: 0.42)]
    return palette[index % palette.count]
}

private struct TreemapTileView: View {
    let children: [StorageChildSummary]
    let totalSize: Int64
    let selectedID: String?
    let onSelect: (StorageChildSummary) -> Void
    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { geometry in
            let placements = TreemapPartition.layout(children, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                if children.isEmpty {
                    ContentUnavailableView("No measurable storage", systemImage: "square.grid.2x2", description: Text("All items are available in the contents list."))
                }
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    if let rect = placements[child.id], rect.width > 8, rect.height > 8 {
                        let active = selectedID == child.id || hoveredID == child.id
                        Button { onSelect(child) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                if rect.width > 100 && rect.height > 110 {
                                    Image(systemName: child.isDirectory ? "folder" : "doc")
                                        .font(.system(size: 22, weight: .light)).opacity(0.85)
                                    Spacer(minLength: 0)
                                }
                                if rect.width > 75 && rect.height > 55 {
                                    Text(child.name).font(.system(size: rect.width > 180 ? 17 : 12, weight: .semibold))
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(mapSize(child.size))
                                        .font(.system(size: rect.width > 180 && rect.height > 150 ? 27 : 13, weight: .medium, design: .rounded))
                                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                                }
                                if rect.width > 110 && rect.height > 170 {
                                    Text("\(Int((Double(child.size ?? 0) / Double(max(1, totalSize)) * 100).rounded()))% of this folder")
                                        .font(.caption).opacity(0.8)
                                }
                            }
                            .padding(rect.width > 100 && rect.height > 110 ? 20 : 10)
                            .frame(width: max(0, rect.width - 6), height: max(0, rect.height - 6), alignment: .bottomLeading)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [mapColor(index).opacity(active ? 0.82 : 0.95), mapColor(index)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(active ? 0.95 : 0.14), lineWidth: active ? 3 : 1))
                        }
                        .buttonStyle(.plain)
                        .position(x: rect.midX, y: rect.midY)
                        .onHover { hoveredID = $0 ? child.id : nil }
                        .accessibilityLabel("\(child.name), \(mapSize(child.size))")
                        .help("Select \(child.name) to inspect this \(child.isDirectory ? "folder" : "file")")
                    }
                }
            }
        }
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
        let fraction = Double(firstWeight) / total
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
