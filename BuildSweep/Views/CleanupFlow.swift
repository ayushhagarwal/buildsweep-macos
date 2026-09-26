import AppKit
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
                        Text("\(plan.items.count) items · \(BuildSweepFormatters.bytes(plan.selectedSize)) estimated")
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
                    Text("Selected files move to Trash. Emptying Trash makes them unrecoverable.")
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
                        Text(value.item.url?.path(percentEncoded: false) ?? value.item.id)
                            .font(.caption.monospaced()).textSelection(.enabled)
                        Text("Why: \(eligibilityReason(for: value.item))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Effect: \(expectedEffect(for: value.item))")
                            .font(.caption).foregroundStyle(.secondary)
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

    private func eligibilityReason(for item: StorageItem) -> String {
        switch item.kind {
        case .derivedData: "Known Xcode Derived Data project folder."
        case .compilerCache: "Known Xcode compiler cache folder."
        case .archive: "Recognized .xcarchive package under Xcode Archives."
        case .deviceSupport: "Recognized immediate child of an Xcode DeviceSupport folder."
        case .documentation: "Known Xcode documentation cache location."
        case .deviceLog: "Known Xcode device log location; review its contents first."
        case .xcodeCache: "Known direct child of the optional Xcode cache folder."
        case .cursorCache, .codexCache, .claudeCache: "Allowlisted cache or log folder in the granted tool location."
        case .previewData, .simulatorDevice, .simulatorRuntime: "This item is not currently eligible for cleanup."
        }
    }

    private func expectedEffect(for item: StorageItem) -> String {
        switch item.kind {
        case .derivedData: "Xcode can rebuild this data; the next build may take longer."
        case .compilerCache: "Xcode recreates these caches as needed."
        case .archive: "Removes this archive and its dSYMs; you may lose the ability to distribute or symbolicate this build."
        case .deviceSupport: "Xcode may need to download symbols again to debug devices on this OS version."
        case .documentation: "Xcode may need to download this documentation again."
        case .deviceLog: "Removes diagnostic records that may help investigate device issues."
        case .xcodeCache: "Xcode can recreate this cache."
        case .cursorCache, .codexCache, .claudeCache: "The tool may regenerate cache data; logs can contain useful diagnostics."
        case .previewData, .simulatorDevice, .simulatorRuntime: item.risk.explanation
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName)
                            Text(item.message).font(.caption).foregroundStyle(.secondary)
                            if let trashedURL = item.trashedURL {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([trashedURL])
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
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
                    Text("Files moved to Trash can be restored from Finder until Trash is emptied. BuildSweep cannot recover items after Trash is emptied. Permanent Simulator actions are listed separately above.")
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
