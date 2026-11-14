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

    /// Resolved against the city recorded with the scan, not the current one, so the row
    /// keeps showing what the user was actually told at the time.
    private var destinations: [WasteStream] {
        guard let engine = app.engine(for: record.cityID) else { return [] }
        return engine.verdicts(for: record.product).groupedByStream.map(\.stream)
    }
}
