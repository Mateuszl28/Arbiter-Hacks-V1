import SwiftUI
import SwiftData

/// The things you still have to carry somewhere.
struct TakeBackView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    /// Only what has not been taken back yet. The filter lives in the query so a ticked
    /// item disappears without any manual bookkeeping.
    @Query(
        filter: #Predicate<ScanRecord> { $0.returnedAt == nil },
        sort: \ScanRecord.scannedAt,
        order: .reverse
    )
    private var pending: [ScanRecord]

    @State private var showingDone = false

    private var list: TakeBackList {
        TakeBackList.build(
            records: pending.map {
                // persistentModelID is SwiftData's own identity, so the engine needs no
                // extra attribute on the model — and no schema change to get one.
                (key: TakeBackList.RecordKey($0.persistentModelID),
                 productName: $0.displayTitle,
                 scannedAt: $0.scannedAt,
                 cityID: $0.cityID,
                 product: $0.product)
            },
            library: app.library
        )
    }

    var body: some View {
        Group {
            if list.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to carry", systemImage: "checkmark.circle")
                } description: {
                    Text("Deposit bottles and drop-off items will collect here as you scan them. Everything else just goes in a bin.")
                }
            } else {
                List {
                    if !list.valueByCurrency.isEmpty {
                        totalsSection
                    }
                    ForEach(list.destinations) { destination in
                        destinationSection(destination)
                    }
                }
            }
        }
        .navigationTitle("Take back")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingDone = true
                } label: {
                    Label("Taken back", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showingDone) {
            TakenBackHistorySheet()
        }
    }

    private var totalsSection: some View {
        Section {
            ForEach(list.valueByCurrency, id: \.currency) { entry in
                HStack {
                    Image(systemName: "banknote")
                        .foregroundStyle(.green)
                    Text(entry.amount.formattedCurrency(code: entry.currency))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("waiting to be reclaimed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Based on each city's deposit rate, for things you scanned there.")
        }
    }

    private func destinationSection(_ destination: TakeBackList.Destination) -> some View {
        Section {
            ForEach(destination.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.productName)
                            .font(.subheadline.weight(.medium))
                        Text(item.componentSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if item.unitCount > 1 {
                            Text("\(item.unitCount) items")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let value = item.value {
                        Text(value.formattedCurrency(code: destination.currencyCode))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .trailing) {
                    Button {
                        markReturned(item)
                    } label: {
                        Label("Taken back", systemImage: "checkmark")
                    }
                    .tint(.green)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Taken back") { markReturned(item) }
            }

            Button {
                for item in destination.items { markReturned(item) }
            } label: {
                Label("Mark all taken back", systemImage: "checkmark.circle")
                    .font(.footnote.weight(.medium))
            }
        } header: {
            HStack(spacing: 10) {
                StreamBadge(stream: destination.stream, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(destination.stream.localName ?? destination.stream.name)
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                    Text("\(destination.cityName) · \(destination.unitCount) \(destination.unitCount == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                Spacer(minLength: 0)
                if destination.totalValue > 0 {
                    Text(destination.totalValue.formattedCurrency(code: destination.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .textCase(nil)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            if let instruction = instruction(for: destination) {
                Text(instruction)
            }
        }
    }

    /// Reuses the city's own wording rather than inventing a second set of instructions.
    private func instruction(for destination: TakeBackList.Destination) -> String? {
        guard let ruleset = app.library.cities.first(where: { $0.displayName == destination.cityName }) else {
            return nil
        }
        return ruleset.rules.first { $0.stream == destination.stream.id }?.instruction
    }

    private func markReturned(_ item: TakeBackList.Item) {
        guard let record = pending.first(where: {
            TakeBackList.RecordKey($0.persistentModelID) == item.recordKey
        }) else { return }
        record.returnedAt = Date()
        try? context.save()
    }
}

/// What has already been carried away, so ticking something off is undoable.
private struct TakenBackHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<ScanRecord> { $0.returnedAt != nil },
        sort: \ScanRecord.returnedAt,
        order: .reverse
    )
    private var returned: [ScanRecord]

    var body: some View {
        NavigationStack {
            Group {
                if returned.isEmpty {
                    ContentUnavailableView(
                        "Nothing taken back yet",
                        systemImage: "shippingbox",
                        description: Text("Items you tick off will be listed here.")
                    )
                } else {
                    List {
                        ForEach(returned) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.displayTitle)
                                        .font(.subheadline)
                                    if let date = record.returnedAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Button("Undo") {
                                    record.returnedAt = nil
                                    try? context.save()
                                }
                                .font(.footnote)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Taken back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
