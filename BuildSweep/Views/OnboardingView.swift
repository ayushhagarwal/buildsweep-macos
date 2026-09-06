import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    private let stepTitles = ["Understand", "Access", "Scan"]

    var body: some View {
        ZStack {
            AppBackground()
            HStack(spacing: 0) {
                visualStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.35)
                copyPane
                    .frame(maxWidth: 420)
                    .padding(36)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .onAppear {
            if model.developerRoot != nil { step = 2 }
        }
        .onChange(of: model.developerRoot?.id) { _, id in
            if id != nil { advance(to: 2) }
        }
    }

    private var visualStage: some View {
        ZStack {
            switch step {
            case 0: StorageStackVisual()
            case 1: AccessFolderVisual()
            default: ScanRingVisual(model: model)
            }
        }
        .animation(BuildSweepTheme.animation(reduceMotion), value: step)
        .padding(40)
    }

    private var copyPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepIndicator
                .padding(.bottom, 28)

            Group {
                switch step {
                case 0: privacyCopy
                case 1: accessCopy
                default: scanningCopy
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(copyTransition)

            Spacer(minLength: 24)

            footer
        }
    }

    private var copyTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(index == step ? BuildSweepTheme.accent : Color.secondary.opacity(0.22))
                        .frame(height: 4)
                    Text(stepTitles[index])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(index == step ? .primary : .secondary)
                }
            }
        }
    }

    private var privacyCopy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Understand Xcode storage")
                .font(.largeTitle.bold())
            Text("BuildSweep shows which generated files take space and explains what happens before anything is removed.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                InfoChip(title: "Local metadata only", systemImage: "macbook")
                InfoChip(title: "No source contents", systemImage: "doc.text.magnifyingglass")
                InfoChip(title: "No tracking", systemImage: "hand.raised")
            }
            .padding(.top, 8)
        }
    }

    private var accessCopy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Library/Developer")
                .font(.largeTitle.bold())
            Text("macOS requires you to explicitly choose this folder. BuildSweep stores a revocable security-scoped bookmark so access survives relaunches.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(BuildSweepTheme.accent)
                Text("~/Library/Developer")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .surfaceCard(cornerRadius: 12)

            if let message = model.appMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Choose this folder — never your home folder or all of Library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scanningCopy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scanning Xcode storage")
                .font(.largeTitle.bold())
            Text(scanDetail)
                .font(.title3)
                .foregroundStyle(.secondary)
            ScanCategoryChecklist(model: model)
                .padding(.top, 6)
        }
        .onChange(of: model.scanState) { _, value in
            if value == .complete { model.selection = .overview }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if step == 0 {
                Button("Continue") { advance(to: 1) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else if step == 1 {
                Button("Choose Developer Folder") {
                    Task {
                        await model.grantDeveloperAccess()
                        if model.developerRoot != nil { advance(to: 2) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if case .complete = model.scanState {
                Button("Open Overview") { model.completeOnboarding() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private func advance(to next: Int) {
        withAnimation(BuildSweepTheme.animation(reduceMotion)) { step = next }
    }

    private var scanDetail: String {
        if case .scanning(let completed, let total) = model.scanState {
            return "Completed \(completed) of \(total) categories"
        }
        return "Your first overview is ready."
    }
}

private struct StorageStackVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let slabs: [(title: String, fill: Color, offset: CGFloat)] = [
        ("Derived Data", BuildSweepTheme.categoryFill(for: .derivedData), 0),
        ("Archives", BuildSweepTheme.categoryFill(for: .archives), 28),
        ("Caches", BuildSweepTheme.categoryFill(for: .cachesAndLogs), 56)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(slabs.enumerated()), id: \.offset) { index, slab in
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(index == 1 ? BuildSweepTheme.surfaceEmphasized : BuildSweepTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(BuildSweepTheme.border, lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        HStack(spacing: 12) {
                            Circle().fill(slab.fill).frame(width: 10, height: 10)
                            Text(slab.title).font(.headline)
                        }
                        .padding(.leading, 28)
                    }
                    .frame(width: 280, height: 92)
                    .offset(y: appeared ? slab.offset - 28 : 80)
                    .opacity(appeared ? 1 : 0)
                    .rotationEffect(.degrees(appeared ? Double(index - 1) * 3.5 : 8))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                    .animation(
                        BuildSweepTheme.animation(reduceMotion, .spring(response: 0.55, dampingFraction: 0.78).delay(Double(index) * 0.08)),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

private struct AccessFolderVisual: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(BuildSweepTheme.accentSoft)
                .frame(width: 220, height: 220)
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 92, weight: .light))
                .foregroundStyle(BuildSweepTheme.accent)
        }
    }
}

private struct ScanRingVisual: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(BuildSweepTheme.accentSoft, lineWidth: 14)
                .frame(width: 196, height: 196)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(BuildSweepTheme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 196, height: 196)
                .rotationEffect(.degrees(-90))
                .animation(BuildSweepTheme.animation(reduceMotion, .easeInOut(duration: 0.35)), value: progress)
            VStack(spacing: 4) {
                if case .complete = model.scanState {
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(BuildSweepTheme.accent)
                } else {
                    Text(progressLabel)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("scanned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var progress: CGFloat {
        switch model.scanState {
        case .scanning(let completed, let total):
            guard total > 0 else { return 0 }
            return CGFloat(completed) / CGFloat(total)
        case .complete: return 1
        default: return 0.08
        }
    }

    private var progressLabel: String {
        if case .scanning(let completed, let total) = model.scanState {
            return "\(completed)/\(total)"
        }
        return "…"
    }
}

private struct ScanCategoryChecklist: View {
    @Bindable var model: AppModel

    private var categories: [StorageCategoryID] {
        StorageCategoryID.allCases.filter { $0.isScannable && $0 != .aiTools }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                HStack(spacing: 10) {
                    Image(systemName: isComplete(index) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isComplete(index) ? BuildSweepTheme.accent : Color.secondary.opacity(0.45))
                    Text(category.title)
                        .foregroundStyle(isComplete(index) ? .primary : .secondary)
                    Spacer()
                }
                .font(.callout)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    private func isComplete(_ index: Int) -> Bool {
        switch model.scanState {
        case .complete: return true
        case .scanning(let completed, _): return index < completed
        default: return false
        }
    }
}
