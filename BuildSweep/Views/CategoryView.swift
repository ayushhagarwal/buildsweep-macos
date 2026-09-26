import SwiftUI

struct CategoryView: View {
    enum SortOrder: String, CaseIterable, Identifiable {
        case size = "Size"
        case name = "Name"
        case date = "Last Used"
        var id: String { rawValue }
    }

    @Bindable var model: AppModel
    let category: StorageCategoryID
    @State private var sortOrder: SortOrder = .size
    @State private var riskFilter: StorageRisk?

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                header
                    .padding(20)
                    .surfaceCard(cornerRadius: 16)
                    .padding([.horizontal, .top], 16)
                if items.isEmpty {
                    emptyState
                } else {
                    List(items) { item in
                        StorageItemRow(model: model, item: item)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(category.title)
        .searchable(text: $model.searchText, prompt: "Search \(category.title)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 12) {
                    IconTile(systemImage: category.systemImage, tint: BuildSweepTheme.categoryForeground(for: category), size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title).font(.largeTitle.bold())
                        Text("\(items.count) items · \(BuildSweepFormatters.bytes(items.reduce(0) { $0 + $1.size })) estimated")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("Risk", selection: $riskFilter) {
                    Text("All consequences").tag(StorageRisk?.none)
                    ForEach(StorageRisk.allCases, id: \.self) { Text($0.title).tag(StorageRisk?.some($0)) }
                }
                .frame(width: 170)
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 130)
            }

            if let warning = model.snapshot.categories[category]?.warnings.first {
                Label(warning, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if category == .simulators {
                Button("Open Xcode Components") { model.openXcodeComponents() }
                    .buttonStyle(.link)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text(emptyTitle)
            } icon: {
                IconTile(systemImage: category.systemImage, tint: BuildSweepTheme.categoryForeground(for: category), size: 52)
            }
        } description: {
            Text(emptyDescription)
        } actions: {
            if category == .aiTools && !model.hasAnyAIRoot {
                SettingsLink {
                    Text("Open Settings")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Scan Again") { model.startScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if category == .aiTools && !model.hasAnyAIRoot {
            return "Grant an AI tool folder"
        }
        return "Nothing found"
    }

    private var emptyDescription: String {
        if category == .aiTools && !model.hasAnyAIRoot {
            return "Grant Cursor, Codex, or Claude folders in Settings › Privacy. BuildSweep scans cache and logs only; chats and skills are never read."
        }
        if category == .aiTools {
            return "No AI tool caches were found in the granted folders."
        }
        return "Run a scan, adjust the search, or confirm that Xcode has created this kind of storage."
    }

    private var items: [StorageItem] {
        var values = model.snapshot.categories[category]?.items ?? []
        if !model.searchText.isEmpty {
            values = values.filter {
                $0.displayName.localizedCaseInsensitiveContains(model.searchText) ||
                $0.metadata.values.contains { $0.localizedCaseInsensitiveContains(model.searchText) }
            }
        }
        if let riskFilter { values = values.filter { $0.risk == riskFilter } }
        switch sortOrder {
        case .size: values.sort { $0.size > $1.size }
        case .name: values.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .date: values.sort { ($0.lastUsedAt ?? $0.modifiedAt ?? .distantPast) > ($1.lastUsedAt ?? $1.modifiedAt ?? .distantPast) }
        }
        return values
    }
}

private struct StorageItemRow: View {
    @Bindable var model: AppModel
    let item: StorageItem
    @State private var expanded = false
    @State private var hovering = false
    @State private var childInspection: StorageChildrenInspection?
    @State private var inspectionError: String?
    @State private var isInspecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { model.selectedItemIDs.contains(item.id) },
                    set: { _ in model.toggleSelection(item) }
                ))
                .labelsHidden()
                .disabled(item.action == .inspectionOnly)

                Image(systemName: icon)
                    .foregroundStyle(item.action == .inspectionOnly ? Color.secondary : BuildSweepTheme.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName).fontWeight(.semibold).lineLimit(1)
                    Text(item.url?.path(percentEncoded: false) ?? item.metadata["Runtime"] ?? "Managed by Xcode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dateLabel).font(.caption2).foregroundStyle(.tertiary)
                    Text(BuildSweepFormatters.date(item.lastUsedAt ?? item.modifiedAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 120, alignment: .trailing)
                RiskBadge(risk: item.risk)
                    .frame(width: 110)
                Text(BuildSweepFormatters.bytes(item.size))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 90, alignment: .trailing)
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide details" : "Show details")
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.risk.explanation).foregroundStyle(.secondary)
                    if !item.metadata.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                            ForEach(item.metadata.keys.sorted(), id: \.self) { key in
                                GridRow {
                                    Text(key).foregroundStyle(.secondary)
                                    Text(item.metadata[key] ?? "")
                                }
                            }
                        }
                        .font(.caption)
                    }
                    childContents
                    HStack {
                        Button("Reveal in Finder") { model.reveal(item) }.disabled(item.url == nil)
                        Button("Copy Path") { model.copyPath(item) }.disabled(item.url == nil)
                    }
                    .buttonStyle(.link)
                }
                .padding(.leading, 62)
                .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(hovering ? BuildSweepTheme.hoverFill : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .task(id: expanded) {
            guard expanded, let url = item.url else { return }
            isInspecting = true
            inspectionError = nil
            defer { isInspecting = false }
            do {
                childInspection = try await DirectorySizer().inspectImmediateChildren(of: url)
            } catch is CancellationError {
                return
            } catch {
                inspectionError = error.localizedDescription
            }
        }
        .contextMenu {
            Button("Reveal in Finder") { model.reveal(item) }.disabled(item.url == nil)
            Button("Copy Path") { model.copyPath(item) }.disabled(item.url == nil)
        }
    }

    @ViewBuilder
    private var childContents: some View {
        if let url = item.url {
            VStack(alignment: .leading, spacing: 6) {
                Text("Contents").font(.caption.weight(.semibold))
                if isInspecting {
                    ProgressView("Measuring immediate contents…").controlSize(.small)
                } else if let inspectionError {
                    Text("Couldn’t inspect this folder: \(inspectionError)")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let childInspection {
                    if childInspection.totalCount == 0 {
                        Text("No contents to show.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(childInspection.children) { child in
                            HStack(spacing: 8) {
                                Image(systemName: child.isDirectory ? "folder" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(child.name).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(child.size.map(BuildSweepFormatters.bytes) ?? "Size unavailable")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        if childInspection.totalCount > childInspection.children.count {
                            Text("Showing \(childInspection.children.count) of \(childInspection.totalCount) immediate items.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Folder sizes are estimates based on allocated file space.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var icon: String {
        switch item.kind {
        case .archive: "archivebox.fill"
        case .simulatorDevice: "iphone.gen3"
        case .simulatorRuntime: "square.stack.3d.up"
        case .deviceLog: "doc.text"
        case .documentation: "book.closed"
        case .cursorCache, .codexCache, .claudeCache: "cpu"
        default: "externaldrive.fill"
        }
    }

    private var dateLabel: String {
        if item.lastUsedAt != nil { return "Last accessed" }
        if item.modifiedAt != nil { return "Modified" }
        return "Date unavailable"
    }
}
