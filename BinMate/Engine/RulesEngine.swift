import Foundation

/// How confident BinMate is in a verdict, and why.
///
/// Surfacing this is a deliberate product decision. The failure mode of every sorting
/// app is confident nonsense, and a user who is told "we matched your exact material"
/// versus "we fell back to the general plastic rule" can calibrate their trust. It also
/// doubles as a to-do list for whoever maintains the rulesets.
enum MatchQuality: Hashable, Sendable {
    /// A rule named this exact material *and* this exact part.
    case exactWithShape
    /// A rule named this exact material, for any part.
    case exactMaterial
    /// No rule for the material itself, so a broader ancestor rule applied.
    case inherited(from: TaxonomyID)
    /// Nothing matched. The city's catch-all stream applies.
    case cityDefault

    var label: String {
        switch self {
        case .exactWithShape:
            "Specific rule for this part"
        case .exactMaterial:
            "Specific rule for this material"
        case .inherited(let ancestor):
            "General \(MaterialTaxonomy.displayName(for: ancestor).lowercased()) rule"
        case .cityDefault:
            "No specific rule — default bin"
        }
    }

    var symbol: String {
        switch self {
        case .exactWithShape, .exactMaterial: "checkmark.seal.fill"
        case .inherited: "arrow.up.circle.fill"
        case .cityDefault: "questionmark.circle.fill"
        }
    }

}

/// Where one component goes in one city.
struct BinVerdict: Identifiable, Hashable, Sendable {
    var id: UUID { component.id }
    var component: PackagingComponent
    var stream: WasteStream
    var instruction: String?
    var caution: String?
    var quality: MatchQuality
    /// Why this verdict came out the way it did, in the engine's own terms.
    var explanation: Explanation

    /// The decision, laid out.
    ///
    /// An app that tells someone to put a bottle in a particular bin and cannot say why
    /// is asking to be trusted on authority. Every step the engine took is recorded here
    /// so the screen can show its working — and so a user who disagrees can see exactly
    /// which rule produced the answer rather than arguing with a black box.
    struct Explanation: Hashable, Sendable {
        /// The material as it arrived, canonicalised.
        var material: TaxonomyID
        /// The part, when the data named one.
        var shape: TaxonomyID?
        /// The material the matching rule was actually written for. Differs from
        /// `material` when the answer was inherited — a PP cap matched by a rule about
        /// plastic in general.
        var matchedMaterial: TaxonomyID?
        /// The ancestry walked to get there, nearest first.
        var ancestry: [TaxonomyID]
        /// Shapes the matching rule narrowed itself to, if any.
        var ruleShapes: [TaxonomyID]
        /// Which rule in the ruleset fired, by position — so the file can be opened at
        /// the right line.
        var ruleIndex: Int?
        var cityName: String
        var compiledOn: String
        var sourceName: String

        /// Steps to show, in order. Written as statements a person can check against
        /// the packaging in their hand.
        var steps: [Step] {
            var result: [Step] = [
                Step(
                    label: "Material",
                    detail: MaterialTaxonomy.displayName(for: material),
                    note: material.value
                )
            ]
            if let shape {
                result.append(
                    Step(label: "Part", detail: ShapeTaxonomy.displayName(for: shape), note: shape.value)
                )
            }
            if let matchedMaterial, matchedMaterial != material {
                result.append(
                    Step(
                        label: "Matched as",
                        detail: MaterialTaxonomy.displayName(for: matchedMaterial),
                        note: "no rule for \(MaterialTaxonomy.displayName(for: material).lowercased()) specifically, so the broader rule applies"
                    )
                )
            }
            if !ruleShapes.isEmpty {
                result.append(
                    Step(
                        label: "Rule covers",
                        detail: ruleShapes.map { ShapeTaxonomy.displayName(for: $0).lowercased() }.joined(separator: ", "),
                        note: "this rule applies only to those parts"
                    )
                )
            }
            if matchedMaterial == nil {
                result.append(
                    Step(
                        label: "No rule matched",
                        detail: "\(cityName)'s default bin",
                        note: "nothing in the ruleset covers this material"
                    )
                )
            }
            result.append(
                Step(label: "Source", detail: sourceName, note: "compiled \(compiledOn)")
            )
            return result
        }

        struct Step: Hashable, Sendable, Identifiable {
            var id: String { label + detail }
            var label: String
            var detail: String
            var note: String?
        }
    }

    /// Total deposit reclaimable for this component, accounting for multipacks.
    var depositValue: Decimal? {
        guard let amount = stream.depositAmount else { return nil }
        return amount * Decimal(component.numberOfUnits)
    }
}

/// Resolves packaging components against one city's rules.
///
/// Pure, synchronous and offline by construction. That is what makes the headline
/// interaction possible: switching city re-resolves a whole product instantly, with no
/// request in flight and nothing to fail on stage.
struct RulesEngine: Sendable {
    let ruleset: CityRuleset

    init(ruleset: CityRuleset) {
        self.ruleset = ruleset
    }

    func verdicts(for product: ScannedProduct) -> [BinVerdict] {
        product.components.map(verdict(for:))
    }

    func verdict(for component: PackagingComponent) -> BinVerdict {
        let ancestry = MaterialTaxonomy.ancestry(of: component.material)

        guard let match = bestMatch(for: component) else {
            return BinVerdict(
                component: component,
                stream: ruleset.defaultStream ?? Self.lastResortStream,
                instruction: nil,
                caution: nil,
                quality: .cityDefault,
                explanation: BinVerdict.Explanation(
                    material: component.material,
                    shape: component.shape,
                    matchedMaterial: nil,
                    ancestry: ancestry,
                    ruleShapes: [],
                    ruleIndex: nil,
                    cityName: ruleset.displayName,
                    compiledOn: ruleset.compiledOn,
                    sourceName: ruleset.sourceName
                )
            )
        }

        return BinVerdict(
            component: component,
            stream: ruleset.stream(id: match.rule.stream) ?? Self.lastResortStream,
            instruction: match.rule.instruction,
            caution: match.rule.caution,
            quality: match.quality,
            explanation: BinVerdict.Explanation(
                material: component.material,
                shape: component.shape,
                matchedMaterial: match.matchedMaterial,
                ancestry: ancestry,
                ruleShapes: match.rule.shapes ?? [],
                ruleIndex: match.index,
                cityName: ruleset.displayName,
                compiledOn: ruleset.compiledOn,
                sourceName: ruleset.sourceName
            )
        )
    }

    // MARK: - Matching

    private struct Match {
        var rule: BinRule
        var quality: MatchQuality
        /// The material the rule was written for, which is what the explanation needs.
        var matchedMaterial: TaxonomyID
        /// Position in the ruleset, so the explanation can point at the rule itself.
        var index: Int
    }

    /// Walks the material's ancestry nearest-first and, at each level, prefers a rule
    /// that also names the component's shape.
    ///
    /// Order matters more than it looks. A PET bottle in Berlin must hit the
    /// `[en:pet] + [en:bottle] -> Pfand` rule before it hits the broader
    /// `[en:plastic] -> yellow bin` rule, otherwise the app sends a user to throw away
    /// a bottle worth 25 cents.
    private func bestMatch(for component: PackagingComponent) -> Match? {
        let ancestry = MaterialTaxonomy.ancestry(of: component.material)

        for (depth, material) in ancestry.enumerated() {
            let candidates = ruleset.rules.enumerated().filter { $0.element.materials.contains(material) }
            guard !candidates.isEmpty else { continue }

            if let shape = component.shape,
               let shapeSpecific = candidates.first(where: { $0.element.shapes?.contains(shape) == true }) {
                return Match(
                    rule: shapeSpecific.element,
                    quality: depth == 0 ? .exactWithShape : .inherited(from: material),
                    matchedMaterial: material,
                    index: shapeSpecific.offset
                )
            }

            // A rule that names shapes must not catch components with a different shape.
            if let general = candidates.first(where: { $0.element.shapes == nil || $0.element.shapes?.isEmpty == true }) {
                return Match(
                    rule: general.element,
                    quality: depth == 0 ? .exactMaterial : .inherited(from: material),
                    matchedMaterial: material,
                    index: general.offset
                )
            }
        }
        return nil
    }

    /// Used only if a ruleset references a stream id it never defines. Rulesets are
    /// validated on load, so this exists to keep the UI honest rather than to crash.
    private static let lastResortStream = WasteStream(
        id: "unknown",
        name: "Ask your local service",
        localName: nil,
        colorHex: "8E8E93",
        symbol: "questionmark",
        kind: .residual,
        depositAmount: nil,
        depositCurrencyCode: nil
    )
}

// MARK: - Aggregates

extension Array where Element == BinVerdict {
    /// Groups verdicts by stream, preserving first-seen order, so the result screen can
    /// show "two things go in the yellow bin" as one card.
    var groupedByStream: [(stream: WasteStream, verdicts: [BinVerdict])] {
        var order: [String] = []
        var buckets: [String: [BinVerdict]] = [:]

        for verdict in self {
            if buckets[verdict.stream.id] == nil { order.append(verdict.stream.id) }
            buckets[verdict.stream.id, default: []].append(verdict)
        }
        return order.compactMap { id in
            guard let group = buckets[id], let stream = group.first?.stream else { return nil }
            return (stream, group)
        }
    }

    /// Distinct destinations involved. The number people care about: "this one product
    /// goes to four different places".
    var destinationCount: Int {
        Set(map(\.stream.id)).count
    }

    var totalDeposit: Decimal {
        reduce(Decimal.zero) { $0 + ($1.depositValue ?? 0) }
    }

    var depositCurrencyCode: String? {
        first(where: { $0.stream.isDeposit })?.stream.depositCurrencyCode
    }
}
