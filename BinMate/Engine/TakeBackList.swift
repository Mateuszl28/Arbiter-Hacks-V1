import Foundation

/// The things you cannot simply put in a bin.
///
/// Two kinds of packaging need a separate trip: deposit items, which are worth money, and
/// drop-off items, which are refused at the kerb. The app already knew about both and did
/// nothing with them — it reported a reclaimable total and left the user to remember
/// which bottles it meant. This turns that into a list you can tick off.
///
/// Pure, like everything else in the engine: it takes records and a library and returns
/// values, so the arithmetic is asserted rather than demonstrated.
struct TakeBackList: Sendable {
    /// Identifies a history record without this file knowing what SwiftData is. The
    /// caller passes whatever it uses — `persistentModelID` in the app — and gets the
    /// same value back on the way out.
    typealias RecordKey = AnyHashable

    /// One scanned product that still needs taking somewhere.
    struct Item: Identifiable, @unchecked Sendable {
        var id: String
        var recordKey: RecordKey
        var productName: String
        var scannedAt: Date
        var cityName: String
        var stream: WasteStream
        /// Parts of this product bound for that destination.
        var componentSummary: String
        var unitCount: Int
        var value: Decimal?
    }

    /// A trip: everything going to the same place, in the same city.
    struct Destination: Identifiable, @unchecked Sendable {
        var id: String
        var stream: WasteStream
        var cityName: String
        var items: [Item]

        var totalValue: Decimal {
            items.reduce(Decimal.zero) { $0 + ($1.value ?? 0) }
        }

        var currencyCode: String? { stream.depositCurrencyCode }

        var unitCount: Int {
            items.reduce(0) { $0 + $1.unitCount }
        }
    }

    var destinations: [Destination]

    var isEmpty: Bool { destinations.isEmpty }

    /// Totals per currency, because a user who has travelled may hold euros and dollars.
    var valueByCurrency: [(currency: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for destination in destinations {
            guard let currency = destination.currencyCode, destination.totalValue > 0 else { continue }
            totals[currency, default: 0] += destination.totalValue
        }
        return totals
            .map { (currency: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// Builds the list from history.
    ///
    /// Each record is re-resolved against the city it was scanned in, not the city
    /// currently selected: a bottle scanned in Berlin is worth 25 cents at a German
    /// machine no matter where its owner is standing today.
    static func build(
        records: [(key: RecordKey, productName: String, scannedAt: Date, cityID: String, product: ScannedProduct)],
        library: RulesLibrary
    ) -> TakeBackList {
        var grouped: [String: Destination] = [:]
        var order: [String] = []

        for record in records {
            guard let ruleset = library.city(id: record.cityID) else { continue }
            let verdicts = RulesEngine(ruleset: ruleset).verdicts(for: record.product)

            // Only destinations that need a trip. A kerbside bin is not a to-do.
            let actionable = verdicts.filter {
                $0.stream.kind == .deposit || $0.stream.kind == .dropOff
            }
            guard !actionable.isEmpty else { continue }

            for (streamID, group) in Dictionary(grouping: actionable, by: { $0.stream.id }) {
                guard let stream = group.first?.stream else { continue }
                let key = "\(record.cityID)|\(streamID)"
                if grouped[key] == nil {
                    order.append(key)
                    grouped[key] = Destination(
                        id: key,
                        stream: stream,
                        cityName: ruleset.displayName,
                        items: []
                    )
                }

                let units = group.reduce(0) { $0 + $1.component.numberOfUnits }
                let value = group.compactMap(\.depositValue).reduce(Decimal.zero, +)

                // Built as a local first: appending to `grouped[key]` while also reading
                // its count would be two overlapping accesses to the same storage.
                let position = grouped[key]?.items.count ?? 0
                let item = Item(
                        id: "\(key)-\(position)",
                        recordKey: record.key,
                        productName: record.productName,
                        scannedAt: record.scannedAt,
                        cityName: ruleset.displayName,
                        stream: stream,
                        componentSummary: group
                            .map(\.component.headline)
                            .joined(separator: ", "),
                        unitCount: units,
                        value: value > 0 ? value : nil
                )
                grouped[key]?.items.append(item)
            }
        }

        let destinations = order.compactMap { grouped[$0] }
            // Money first — that is the one people act on.
            .sorted { lhs, rhs in
                if (lhs.totalValue > 0) != (rhs.totalValue > 0) { return lhs.totalValue > 0 }
                return lhs.totalValue > rhs.totalValue
            }

        return TakeBackList(destinations: destinations)
    }
}
