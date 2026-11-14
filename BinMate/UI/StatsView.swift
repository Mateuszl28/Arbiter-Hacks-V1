import SwiftUI
import SwiftData

/// What the household has actually sorted.
///
/// Every figure is derived from real history resolved against the rules that were in
/// force for each scan. There is no invented "CO₂ saved" number: BinMate cannot know
/// what the user would otherwise have done, and a fabricated impact figure would
/// undermine the one thing the app is for, which is being right.
struct StatsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var records: [ScanRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("No numbers yet", systemImage: "chart.bar")
                    } description: {
                        Text("Sort a few items and BinMate will summarise where they went.")
                    }
                    .padding(.top, 60)
                } else {
                    // Computed exactly once per render and passed down. As a computed
                    // property it was rebuilt separately for the tiles, the bar and the
                    // legend, and because ties between streams do not sort stably, the
                    // bar could end up in a different order from the legend beneath it.
                    let stats = HouseholdStats(records: records, library: app.library)

                    VStack(spacing: 18) {
                        tiles(stats)
                        breakdown(stats)
                        if !stats.depositTotals.isEmpty { deposits(stats) }
                        if stats.partsWithoutLocalRule > 0 { honesty(stats) }
                    }
                    .padding()
                }
            }
            .navigationTitle("Your sorting")
            .background(Color(.systemGroupedBackground))
        }
    }

    private func tiles(_ stats: HouseholdStats) -> some View {
        HStack(spacing: 12) {
            StatTile(value: "\(stats.productCount)", label: stats.productCount == 1 ? "product" : "products", symbol: "cube.box")
            StatTile(value: "\(stats.partCount)", label: "parts sorted", symbol: "arrow.triangle.branch")
            StatTile(value: "\(stats.dayStreak)", label: stats.dayStreak == 1 ? "day streak" : "day streak", symbol: "flame")
        }
    }

    private func breakdown(_ stats: HouseholdStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where things went")
                .font(.subheadline.weight(.semibold))

            // A single stacked bar reads faster than a pie at this size and stays
            // legible with one dominant category.
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(stats.streamTotals, id: \.stream.id) { entry in
                        Rectangle()
                            .fill(entry.stream.color)
                            .frame(width: max(3, geometry.size.width * entry.fraction))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 18)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                ForEach(stats.streamTotals, id: \.stream.id) { entry in
                    HStack(spacing: 10) {
                        StreamBadge(stream: entry.stream, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.stream.name)
                                .font(.subheadline)
                            Text(entry.cityName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("\(entry.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func deposits(_ stats: HouseholdStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Deposits you can reclaim", systemImage: "banknote")
                .font(.subheadline.weight(.semibold))

            ForEach(stats.depositTotals, id: \.currency) { entry in
                HStack {
                    Text(entry.amount.formattedCurrency(code: entry.currency))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(entry.itemCount) returnable \(entry.itemCount == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Based on the deposit rate in each city's ruleset, counted across everything you have scanned.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func honesty(_ stats: HouseholdStats) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(stats.partsWithoutLocalRule) \(stats.partsWithoutLocalRule == 1 ? "part" : "parts") had no specific local rule")
                    .font(.footnote.weight(.semibold))
                Text("Those fell back to a default bin. They are the gaps worth filling in the rulesets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Derives the figures on the stats screen from scan history.
struct HouseholdStats {
    struct StreamTotal {
        var stream: WasteStream
        var cityName: String
        var count: Int
        var fraction: Double
    }

    struct DepositTotal {
        var currency: String
        var amount: Decimal
        var itemCount: Int
    }

    var productCount: Int = 0
    var partCount: Int = 0
    var streamTotals: [StreamTotal] = []
    var depositTotals: [DepositTotal] = []
    var partsWithoutLocalRule: Int = 0
    var dayStreak: Int = 0

    init(records: [ScanRecord], library: RulesLibrary) {
        productCount = records.count

        // Keyed by city and stream, because "Recycling" in San Francisco and "Paper" in
        // Berlin are different destinations and must not be merged into one bar.
        var counts: [String: (stream: WasteStream, cityName: String, count: Int)] = [:]
        var deposits: [String: (amount: Decimal, items: Int)] = [:]

        for record in records {
            guard let ruleset = library.city(id: record.cityID) else { continue }
            let engine = RulesEngine(ruleset: ruleset)

            for verdict in engine.verdicts(for: record.product) {
                partCount += verdict.component.numberOfUnits

                let key = "\(record.cityID)|\(verdict.stream.id)"
                let existing = counts[key]
                counts[key] = (
                    verdict.stream,
                    ruleset.displayName,
                    (existing?.count ?? 0) + verdict.component.numberOfUnits
                )

                if verdict.quality == .cityDefault {
                    partsWithoutLocalRule += verdict.component.numberOfUnits
                }

                if let value = verdict.depositValue,
                   let currency = verdict.stream.depositCurrencyCode {
                    let running = deposits[currency] ?? (0, 0)
                    deposits[currency] = (
                        running.amount + value,
                        running.items + verdict.component.numberOfUnits
                    )
                }
            }
        }

        let total = Double(counts.values.reduce(0) { $0 + $1.count })
        streamTotals = counts.values
            .map { entry in
                StreamTotal(
                    stream: entry.stream,
                    cityName: entry.cityName,
                    count: entry.count,
                    fraction: total > 0 ? Double(entry.count) / total : 0
                )
            }
            // Ties broken by a stable key. Swift's sort is not guaranteed stable and the
            // input comes from a dictionary, so without this two streams with equal
            // counts could swap places between renders.
            .sorted {
                $0.count == $1.count
                    ? ($0.cityName, $0.stream.id) < ($1.cityName, $1.stream.id)
                    : $0.count > $1.count
            }

        depositTotals = deposits
            .map { DepositTotal(currency: $0.key, amount: $0.value.amount, itemCount: $0.value.items) }
            .sorted { $0.amount > $1.amount }

        dayStreak = Self.streak(from: records.map(\.scannedAt))
    }

    /// Consecutive days with at least one scan, counting back from today. A streak that
    /// ended yesterday still counts as current, so the user has the rest of today to
    /// keep it alive.
    private static func streak(from dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        let calendar = Calendar.current
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: Date())

        guard let mostRecent = days.max() else { return 0 }
        let gap = calendar.dateComponents([.day], from: mostRecent, to: today).day ?? 0
        guard gap <= 1 else { return 0 }

        var streak = 0
        var cursor = mostRecent
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
