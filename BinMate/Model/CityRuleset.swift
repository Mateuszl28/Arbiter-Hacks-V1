import Foundation

/// A collection point a city actually provides: a coloured bin, a bottle bank, a
/// deposit-return machine, a drop-off centre.
struct WasteStream: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case recycling
        case organic
        case residual
        /// Taken back by a shop or machine in exchange for a deposit.
        case deposit
        /// Hazardous or bulky waste that needs a staffed drop-off point.
        case dropOff
    }

    /// Stable key referenced by rules within the same ruleset.
    var id: String
    /// English name, since judges and users of the app read English.
    var name: String
    /// What the locals call it, e.g. "Gelbe Tonne". Shown as a subtitle so the app is
    /// usable by someone standing in front of a real bin in a country they just moved to.
    var localName: String?
    var colorHex: String
    var symbol: String
    var kind: Kind
    /// Refund per item, for deposit streams only.
    var depositAmount: Decimal?
    var depositCurrencyCode: String?

    var isDeposit: Bool { kind == .deposit }
}

/// Maps packaging onto a stream. The `materials` list is matched against a component's
/// material *and its ancestors*; `shapes`, when present, narrows the rule to specific
/// parts, which is how "a PET bottle is a deposit item but PET film is not" gets expressed.
struct BinRule: Hashable, Codable, Sendable {
    var materials: [TaxonomyID]
    var shapes: [TaxonomyID]?
    var stream: String
    /// Imperative, one line, what to physically do. "Crush it flat. Leave the cap on."
    var instruction: String?
    /// The thing people get wrong often enough to warrant a warning.
    var caution: String?
}

/// Everything BinMate knows about how one city sorts waste.
///
/// Rulesets are plain JSON on purpose. Adding a city is a data change, not a code
/// change, which is the whole point of the design: the hard part of this problem is
/// not classification, it is that the right answer is different on every street.
struct CityRuleset: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var displayName: String
    var region: String
    /// Kept as metadata, but not used for layout. Regional-indicator pairs are missing
    /// from the iOS Simulator's font set, where they render as two "missing glyph" boxes
    /// that still occupy space — enough to wrap a one-line chip into two. `regionCode`
    /// below is drawn instead, so the interface looks the same everywhere.
    var flag: String
    /// Two-letter region code, e.g. "DE". Derived from the ruleset id when absent.
    var regionCode: String?
    /// Roughly the city centre. Optional so a hand-written ruleset without coordinates
    /// still loads — it simply never wins a nearest-city search.
    var latitude: Double?
    var longitude: Double?
    /// Date this ruleset was compiled from the cited source, shown in the UI. Recycling
    /// rules change, and an app that quietly serves stale rules is worse than no app.
    var compiledOn: String
    var sourceName: String
    var sourceURL: URL?
    var streams: [WasteStream]
    var rules: [BinRule]
    /// Where anything unmatched goes. Every city has one, and it is never "nowhere".
    var defaultStreamID: String

    func stream(id: String) -> WasteStream? {
        streams.first { $0.id == id }
    }

    var defaultStream: WasteStream? {
        stream(id: defaultStreamID)
    }

    /// Falls back to the id's country prefix — `de-berlin` gives `DE` — so a hand-written
    /// ruleset that omits the field still shows something sensible.
    var displayRegionCode: String {
        if let regionCode, !regionCode.isEmpty { return regionCode.uppercased() }
        let prefix = id.split(separator: "-").first.map(String.init) ?? id
        return String(prefix.prefix(2)).uppercased()
    }

    var subtitle: String { "\(displayName), \(region)" }
}
