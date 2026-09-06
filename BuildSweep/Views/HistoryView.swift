import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
            HStack {
                HStack(spacing: 12) {
                    IconTile(systemImage: "clock.arrow.circlepath", tint: BuildSweepTheme.categoryForeground(for: .history), size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History").font(.largeTitle.bold())
                        Text("Local cleanup receipts. No paths or history leave this Mac.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Clear History", role: .destructive) {
                    Task { await model.clearHistory() }
                }
                .disabled(model.history.isEmpty)
            }
            .padding(20)
            .surfaceCard(cornerRadius: 16)
            .padding([.horizontal, .top], 16)

            if model.history.isEmpty {
                ContentUnavailableView("No cleanup history", systemImage: "clock.arrow.circlepath", description: Text("Successful and failed item results will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.history) { session in
                    DisclosureGroup {
                        ForEach(session.results) { item in
                            HStack {
                                Image(systemName: item.succeeded ? "checkmark.circle" : "xmark.circle")
                                    .foregroundStyle(item.succeeded ? .green : .red)
                                Text(item.displayName)
                                Spacer()
                                Text(item.message).foregroundStyle(.secondary)
                                Text(BuildSweepFormatters.bytes(item.size)).monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(BuildSweepFormatters.bytes(session.recoveredSize) + " recovered")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BuildSweepTheme.accent)
                                Text(session.completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(session.succeededItems.count) succeeded")
                            if !session.failedItems.isEmpty {
                                Text("\(session.failedItems.count) failed").foregroundStyle(.red)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            }
        }
        .navigationTitle("History")
    }
}

