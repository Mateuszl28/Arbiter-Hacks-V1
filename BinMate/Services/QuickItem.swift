import Foundation

/// The everyday things people stand in front of a bin holding.
///
/// Deliberately a plain Foundation enum rather than an `AppEnum`. The Siri and Shortcuts
/// wrapper is thin and untestable without a device; this — the part that can actually be
/// wrong — is asserted in the host test suite alongside the rules engine.
enum QuickItem: String, CaseIterable, Sendable {
    case plasticBottle
    case glassBottle
    case drinksCan
    case glassJar
    case yogurtPot
    case cardboardBox
    case plasticBag
    case beverageCarton
    case compostableCup
    case bottleCap
    case paperLabel
    case foilWrapper

    /// What a person would say out loud, which is also what Siri matches against.
    var displayName: String {
        switch self {
        case .plasticBottle: "plastic bottle"
        case .glassBottle: "glass bottle"
        case .drinksCan: "drinks can"
        case .glassJar: "glass jar"
        case .yogurtPot: "yogurt pot"
        case .cardboardBox: "cardboard box"
        case .plasticBag: "plastic bag"
        case .beverageCarton: "drinks carton"
        case .compostableCup: "compostable cup"
        case .bottleCap: "bottle cap"
        case .paperLabel: "paper label"
        case .foilWrapper: "foil wrapper"
        }
    }

    /// The single component this resolves to.
    ///
    /// A deliberate simplification, and the reason the spoken answer always points back
    /// at the app: a real yogurt pot is three parts in three bins, and Siri answering
    /// "the yellow bin" for the pot alone would be the exact mistake BinMate exists to
    /// correct. `followUp` below carries that caveat.
    var component: PackagingComponent {
        switch self {
        case .plasticBottle:
            PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate")
        case .glassBottle:
            PackagingComponent(shape: "en:bottle", material: "en:clear-glass")
        case .drinksCan:
            PackagingComponent(shape: "en:can", material: "en:aluminium")
        case .glassJar:
            PackagingComponent(shape: "en:jar", material: "en:clear-glass")
        case .yogurtPot:
            PackagingComponent(shape: "en:pot", material: "en:ps-polystyrene")
        case .cardboardBox:
            PackagingComponent(shape: "en:box", material: "en:cardboard")
        case .plasticBag:
            PackagingComponent(shape: "en:bag", material: "en:ldpe-low-density-polyethylene")
        case .beverageCarton:
            PackagingComponent(shape: "en:box", material: "en:beverage-carton")
        case .compostableCup:
            PackagingComponent(shape: "en:cup", material: "en:pla-polylactic-acid")
        case .bottleCap:
            PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene")
        case .paperLabel:
            PackagingComponent(shape: "en:label", material: "en:paper")
        case .foilWrapper:
            PackagingComponent(shape: "en:wrapper", material: "en:aluminium")
        }
    }

    /// Items that are really several parts, where a one-bin answer is incomplete.
    var isMultiPartInReality: Bool {
        switch self {
        case .yogurtPot, .plasticBottle, .glassBottle, .glassJar, .beverageCarton: true
        default: false
        }
    }
}

/// Answers "where does this go" outside the app's UI — for Siri, Shortcuts, and anything
/// else that needs a verdict without a view.
///
/// Reads the same bundled rules and the same stored city as the app, so a spoken answer
/// can never disagree with the screen.
struct BinLookup: Sendable {
    let library: RulesLibrary

    init(library: RulesLibrary = .loadBundled()) {
        self.library = library
    }

    /// The city the user last chose, falling back the same way `AppModel` does.
    func currentCity(defaults: UserDefaults? = nil) -> CityRuleset? {
        let stored = defaults?.string(forKey: SharedDefaults.selectedCityKey)
            ?? SharedDefaults.selectedCityID()
            ?? ""
        return library.city(id: stored) ?? library.fallbackCity
    }

    struct Answer: Sendable {
        var city: CityRuleset
        var verdict: BinVerdict
        var item: QuickItem

        /// One sentence Siri can speak. Written to be heard rather than read: the bin
        /// first, because that is the only part a person standing at a bin needs.
        var spoken: String {
            var parts: [String] = []

            // You go *to* a deposit machine or a drop-off point, but *in* a bin.
            let placement = switch verdict.stream.kind {
            case .deposit, .dropOff: "goes to"
            default: "goes in"
            }

            if let localName = verdict.stream.localName {
                parts.append("A \(item.displayName) \(placement) \(verdict.stream.name.lowercased()) — the \(localName) — in \(city.displayName).")
            } else {
                parts.append("A \(item.displayName) \(placement) \(verdict.stream.name.lowercased()) in \(city.displayName).")
            }

            // Only announce the refund if the city's own instruction has not already said
            // it. Berlin's reads "take it back to any shop and get 25 cents", and hearing
            // the amount twice in one breath sounds like a glitch.
            if let deposit = verdict.depositValue, deposit > 0, !Self.mentionsMoney(verdict.instruction) {
                parts.append("That one is worth \(deposit.formattedCurrency(code: verdict.stream.depositCurrencyCode)) back.")
            }
            if let instruction = verdict.instruction {
                parts.append(instruction)
            }
            if let caution = verdict.caution {
                parts.append(caution)
            }
            if item.isMultiPartInReality {
                parts.append("That is just the main part — scan the barcode to sort the rest of the packaging.")
            }
            return parts.joined(separator: " ")
        }

        /// True when a city's instruction already states a refund in words or figures.
        private static func mentionsMoney(_ instruction: String?) -> Bool {
            guard let instruction else { return false }
            let text = instruction.lowercased()
            let moneyWords = ["cent", "deposit", "refund", "pfand", "crv", "€", "$", "zł"]
            return moneyWords.contains { text.contains($0) }
        }
    }

    func answer(for item: QuickItem, defaults: UserDefaults? = nil) -> Answer? {
        guard let city = currentCity(defaults: defaults) else { return nil }
        return Answer(
            city: city,
            verdict: RulesEngine(ruleset: city).verdict(for: item.component),
            item: item
        )
    }
}
