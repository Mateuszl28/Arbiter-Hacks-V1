import Foundation

/// The rules of one city, read backwards.
///
/// `RulesEngine` answers "where does this part go". This answers the question people
/// actually ask while standing in front of a bin: "what is allowed in *this* one?" Both
/// read the same ruleset, so the two can never contradict each other.
///
/// It also makes the ruleset inspectable. A user who disagrees with an answer can see the
/// exact rule that produced it, and anyone evaluating the app can see precisely how much
/// a given city covers rather than taking the word of a marketing claim.
struct CityGuide: Sendable {
    let ruleset: CityRuleset

    init(ruleset: CityRuleset) {
        self.ruleset = ruleset
    }

    /// One rule, phrased for reading.
    struct Entry: Identifiable, Sendable {
        var id: String
        /// "PET plastic", or "Aluminium, steel, tinplate".
        var materials: String
        /// "bottles only", when the rule is narrowed to particular parts.
        var shapeNote: String?
        var instruction: String?
        var caution: String?
    }

    /// What the ruleset routes to one stream, in the order the engine would try them.
    func entries(forStream streamID: String) -> [Entry] {
        ruleset.rules.enumerated()
            .filter { $0.element.stream == streamID }
            .map { index, rule in
                Entry(
                    id: "\(streamID)-\(index)",
                    materials: rule.materials
                        .map { MaterialTaxonomy.displayName(for: $0) }
                        .joined(separator: ", "),
                    shapeNote: rule.shapes.flatMap { shapes in
                        shapes.isEmpty ? nil : shapes
                            .map { ShapeTaxonomy.displayName(for: $0).lowercased() }
                            .joined(separator: ", ") + " only"
                    },
                    instruction: rule.instruction,
                    caution: rule.caution
                )
            }
    }

    /// Streams in the order they should be listed: the ones with rules first, the
    /// catch-all last, because that is the one you want when nothing else matched.
    var orderedStreams: [WasteStream] {
        let withRules = Set(ruleset.rules.map(\.stream))
        return ruleset.streams.sorted { lhs, rhs in
            let lhsDefault = lhs.id == ruleset.defaultStreamID
            let rhsDefault = rhs.id == ruleset.defaultStreamID
            if lhsDefault != rhsDefault { return rhsDefault }

            let lhsHas = withRules.contains(lhs.id)
            let rhsHas = withRules.contains(rhs.id)
            if lhsHas != rhsHas { return lhsHas }

            return lhs.name < rhs.name
        }
    }

    func isDefaultStream(_ stream: WasteStream) -> Bool {
        stream.id == ruleset.defaultStreamID
    }

    // MARK: - Search

    /// A thing a user might type, and the packaging it stands for.
    struct Candidate: Sendable {
        var label: String
        var component: PackagingComponent
        /// Extra words that should also match, so "trash bag" finds the plastic bag and
        /// "tin" finds the steel can.
        var synonyms: [String]
    }

    struct Result: Identifiable, Sendable {
        var id: String { label }
        var label: String
        var verdict: BinVerdict
    }

    /// Everything searchable: the everyday items Siri knows, plus every material in the
    /// picker so a user who knows the plastic code can look that up directly.
    static let candidates: [Candidate] = {
        var all: [Candidate] = QuickItem.allCases.map {
            Candidate(label: $0.displayName, component: $0.component, synonyms: synonyms(for: $0))
        }
        for material in MaterialTaxonomy.pickerMaterials {
            let name = MaterialTaxonomy.displayName(for: material)
            // Skip materials already covered by a named item, to keep results clean.
            guard !all.contains(where: { $0.label.caseInsensitiveCompare(name) == .orderedSame }) else {
                continue
            }
            all.append(
                Candidate(
                    label: name,
                    component: PackagingComponent(material: material),
                    synonyms: [material.slug.replacingOccurrences(of: "-", with: " ")]
                )
            )
        }
        return all
    }()

    private static func synonyms(for item: QuickItem) -> [String] {
        switch item {
        case .plasticBottle: ["pet", "water bottle", "soda bottle", "drink bottle"]
        case .glassBottle: ["wine bottle", "beer bottle"]
        case .drinksCan: ["tin", "beer can", "soda can", "aluminium can"]
        case .glassJar: ["jam jar", "pickle jar"]
        case .yogurtPot: ["yoghurt", "pot", "tub"]
        case .cardboardBox: ["carton box", "packaging box", "cardboard"]
        case .plasticBag: ["carrier bag", "trash bag", "film", "wrapping"]
        case .beverageCarton: ["tetra pak", "milk carton", "juice carton"]
        case .compostableCup: ["bioplastic", "pla", "biodegradable"]
        case .bottleCap: ["cap", "screw cap", "lid"]
        case .paperLabel: ["sticker", "label"]
        case .foilWrapper: ["aluminium foil", "tin foil", "foil"]
        }
    }

    /// Ranks matches so a typed prefix lands on the obvious answer first.
    func search(_ query: String, limit: Int = 12) -> [Result] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        let engine = RulesEngine(ruleset: ruleset)

        return Self.candidates
            .compactMap { candidate -> (Candidate, Int)? in
                guard let rank = Self.rank(candidate: candidate, needle: needle) else { return nil }
                return (candidate, rank)
            }
            .sorted {
                $0.1 == $1.1 ? $0.0.label < $1.0.label : $0.1 < $1.1
            }
            .prefix(limit)
            .map { candidate, _ in
                Result(label: candidate.label, verdict: engine.verdict(for: candidate.component))
            }
    }

    /// Lower is better: an exact name beats a prefix, which beats a word match anywhere.
    private static func rank(candidate: Candidate, needle: String) -> Int? {
        let label = candidate.label.lowercased()
        if label == needle { return 0 }
        if label.hasPrefix(needle) { return 1 }
        if candidate.synonyms.contains(where: { $0.lowercased() == needle }) { return 2 }
        if candidate.synonyms.contains(where: { $0.lowercased().hasPrefix(needle) }) { return 3 }
        if label.contains(needle) { return 4 }
        if candidate.synonyms.contains(where: { $0.lowercased().contains(needle) }) { return 5 }
        return nil
    }
}
