import SwiftUI
import SwiftData

/// Everything the user has sorted, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var records: [ScanRecord]

    @State private var reopened: ScannedProduct?

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing sorted yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Scan a barcode or try one of the sample products and it will show up here.")
                    }
                } else {
                    List {
                        ForEach(records) { record in
                            Button {
                                reopened = record.product
                            } label: {
                                HistoryRow(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(item: $reopened) { product in
                VerdictView(product: product, recordToHistory: false)
            }
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(records[index])
        }
        try? context.save()
    }
}

struct HistoryRow: View {
    let record: ScanRecord

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Text("\(record.scannedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.cityName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // History is an account of what was actually said. If the rules have been
                // corrected since, the scans they affected are exactly the ones worth
                // mentioning — and the only ones the app can mention honestly.
                reviewNote
            }

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                ForEach(destinations, id: \.id) { stream in
                    Circle()
                        .fill(stream.color)
                        .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                        .frame(width: 12, height: 12)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var reviewNote: some View {
        switch DecisionReview.review(
            recorded: record.decisions,
            product: record.product,
            library: app.library
        ) {
        case .changed(let differences):
            let moved = differences.contains { !$0.sameBin }
            Label(
                moved
                    ? "The rules changed — \(differences.filter { !$0.sameBin }.count) part(s) would go elsewhere now"
                    : "The rules behind this changed, but the bins are the same",
                systemImage: moved ? "exclamationmark.arrow.circlepath" : "arrow.triangle.2.circlepath"
            )
            .font(.caption2)
            .foregroundStyle(moved ? Color.orange : .secondary)
        case .rulesetGone(let cityID):
            Label("\(cityID) is no longer bundled", systemImage: "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .unchanged, .notRecorded:
            EmptyView()
        }
    }

    /// Resolved against the city recorded with the scan, not the current one, so the row
    /// keeps showing what the user was actually told at the time.
    private var destinations: [WasteStream] {
        guard let engine = app.engine(for: record.cityID) else { return [] }
        return engine.verdicts(for: record.product).groupedByStream.map(\.stream)
    }
}
