import SwiftUI

struct PaywallView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var restoring = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                IconTile(systemImage: "infinity.circle.fill", size: 72)
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("BuildSweep Pro").font(.largeTitle.bold())
                    Text("Unlimited safe Xcode storage cleanup. One purchase, no subscription.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 0) {
                    featureRow("Unlimited cleanup sessions", systemImage: "arrow.triangle.2.circlepath")
                    Divider().padding(.leading, 46)
                    featureRow("Every current and future supported category", systemImage: "square.stack.3d.up.fill")
                    Divider().padding(.leading, 46)
                    featureRow("Unlimited scans remain free", systemImage: "magnifyingglass")
                }
                .surfaceCard(cornerRadius: 16)

                Text(model.purchaseProduct?.displayPrice ?? "$4.99")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(BuildSweepTheme.accent)

                Button(purchasing ? "Purchasing…" : "Unlock Lifetime Pro") {
                    purchasing = true
                    Task {
                        await model.purchasePro()
                        purchasing = false
                        if model.isPro { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(purchasing || restoring)

                Button(restoring ? "Restoring…" : "Restore Purchases") {
                    restoring = true
                    Task {
                        await model.restorePurchases()
                        restoring = false
                        if model.isPro { dismiss() }
                    }
                }
                .buttonStyle(.link)
                .disabled(purchasing || restoring)

                if let message = model.purchaseMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Text("Apple processes purchases. Purchasing never starts a cleanup automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(34)
        }
        .buildSweepAppearance()
        .frame(width: 520, height: 620)
    }

    private func featureRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, size: 28)
            Text(title)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
