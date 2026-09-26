import SwiftUI

struct CleanupReviewView: View {
    @Bindable var model: AppModel
    let plan: CleanupPlan
    @Environment(\.dismiss) private var dismiss
    @State private var confirmedPermanent = false
    @State private var executing = false

    private var blocksForRunningXcode: Bool {
        let sensitive: Set<StorageItemKind> = [.derivedData, .compilerCache, .documentation, .previewData, .xcodeCache]
        return model.xcodeIsRunning && plan.items.contains(where: { sensitive.contains($0.item.kind) })
    }

    private var blocksForRunningSimulator: Bool {
        model.simulatorIsRunning && !plan.permanentItems.isEmpty
    }

    private var blocksForRunningCursor: Bool {
        model.cursorIsRunning && plan.items.contains { $0.item.kind == .cursorCache }
    }

    private var blocksForRunningCodex: Bool {
        model.codexIsRunning && plan.items.contains { $0.item.kind == .codexCache }
    }

    private var blocksForRunningClaude: Bool {
        model.claudeIsRunning && plan.items.contains { $0.item.kind == .claudeCache }
    }

    private var canConfirm: Bool {
        !executing
            && !blocksForRunningXcode
            && !blocksForRunningSimulator
            && !blocksForRunningCursor
            && !blocksForRunningCodex
            && !blocksForRunningClaude
            && (plan.permanentItems.isEmpty || confirmedPermanent)
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    IconTile(systemImage: "trash", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review cleanup").font(.largeTitle.bold())
                        Text("\(plan.items.count) items · \(BuildSweepFormatters.bytes(plan.selectedSize)) selected")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !plan.trashItems.isEmpty {
                            planSection(
                                title: "Move to Trash",
                                subtitle: "These items can usually be restored from Trash.",
                                items: plan.trashItems,
                                destructive: false
                            )
                        }
                        if !plan.permanentItems.isEmpty {
                            planSection(
                                title: "Delete permanently",
                                subtitle: "Simulator deletion cannot be undone from Trash.",
                                items: plan.permanentItems,
                                destructive: true
                            )
                            Toggle("I understand that Simulator deletion is permanent.", isOn: $confirmedPermanent)
                                .padding(.horizontal, 4)
                        }
                        if blocksForRunningXcode {
                            warningRow("Quit Xcode before this cleanup can run.")
                        }
                        if blocksForRunningSimulator {
                            warningRow("Quit Simulator before deleting a Simulator device.")
                        }
                        if blocksForRunningCursor {
                            warningRow("Quit Cursor before this cleanup can run.")
                        }
                        if blocksForRunningCodex {
                            warningRow("Quit Codex before this cleanup can run.")
                        }
                        if blocksForRunningClaude {
                            warningRow("Quit Claude before this cleanup can run.")
                        }
                    }
                    .padding(24)
                }

                HStack {
                    Text("Selected files move to Trash.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button(executing ? "Cleaning…" : "Confirm Cleanup") {
                        executing = true
                        Task { await model.executePreservedCleanup() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canConfirm)
                }
                .padding(18)
                .background(BuildSweepTheme.surface)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
        }
        .buildSweepAppearance()
        .frame(minWidth: 660, minHeight: 560)
        .interactiveDismissDisabled(executing)
    }

    private func warningRow(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 14)
    }

    private func planSection(title: String, subtitle: String, items: [CleanupPlanItem], destructive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            ForEach(items) { value in
                HStack {
                    Image(systemName: value.item.action == .trash ? "trash" : "exclamationmark.triangle")
                        .foregroundStyle(destructive ? BuildSweepTheme.important : BuildSweepTheme.accent)
                    VStack(alignment: .leading) {
                        Text(value.item.displayName).fontWeight(.medium)
                        Text(value.item.risk.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(BuildSweepFormatters.bytes(value.item.size)).monospacedDigit()
                }
                .padding(.vertical, 6)
                if value.id != items.last?.id { Divider() }
            }
        }
        .padding(16)
        .background(BuildSweepTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(destructive ? BuildSweepTheme.important.opacity(0.45) : BuildSweepTheme.border, lineWidth: 1)
        }
    }
}

struct CleanupResultView: View {
    let result: CleanupSessionResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    IconTile(
                        systemImage: result.failedItems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        tint: result.failedItems.isEmpty ? BuildSweepTheme.safe : BuildSweepTheme.caution,
                        size: 56
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.failedItems.isEmpty ? "Cleanup complete" : "Cleanup finished with issues")
                            .font(.largeTitle.bold())
                        Text(BuildSweepFormatters.bytes(result.recoveredSize))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(BuildSweepTheme.accent)
                        Text("estimated recovered")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                List(result.results) { item in
                    HStack {
                        Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.succeeded ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                            Text(item.message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(BuildSweepFormatters.bytes(item.size)).monospacedDigit()
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)
                .surfaceCard()

                if result.hadAnySuccess {
                    Text("Files moved to Trash can be restored from Finder until Trash is emptied. Permanent Simulator actions are listed separately above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(26)
        }
        .buildSweepAppearance()
        .frame(minWidth: 620, minHeight: 520)
    }
}
