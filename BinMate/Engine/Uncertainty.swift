import Foundation

/// The distinct reasons a verdict might deserve less than full confidence.
///
/// `MatchQuality` says *how* a rule was matched. This says *why you might want to check*,
/// which is a different question and often has several answers at once. A PP cap in a
/// city whose ruleset is two years old and which narrows some plastic rules by part but
/// not this one is uncertain for three separate reasons, and collapsing those into a
/// single percentage would discard exactly the information a user needs to act.
///
/// Each reason is phrased as something a person can do something about.
enum UncertaintyReason: Hashable, Sendable {
    /// The material is not in the bundled taxonomy at all, so even the ancestry walk had
    /// nothing to work with.
    case materialNotRecognised(TaxonomyID)
    /// No rule names this material; a broader ancestor rule applied.
    case noRuleForMaterial(matched: TaxonomyID)
    /// Nothing matched. The city's catch-all applies.
    case noRuleAtAll
    /// The matching rule applies to any part, but this city *does* narrow other rules for
    /// the same material by part — so the part plausibly matters and this answer may be
    /// the general case rather than the right one.
    case ruleIgnoresPart
    /// The ruleset has not been recompiled in a long time. Municipal rules change.
    case rulesetMayBeStale(compiledOn: String, monthsOld: Int)

    var summary: String {
        switch self {
        case .materialNotRecognised(let material):
            "\(material.humanized) is not a material BinMate knows."
        case .noRuleForMaterial(let matched):
            "No rule for this material specifically, so the general \(MaterialTaxonomy.displayName(for: matched).lowercased()) rule applied."
        case .noRuleAtAll:
            "Nothing in this city's ruleset covers it, so the default bin applied."
        case .ruleIgnoresPart:
            "The rule that matched covers any part. This city treats some parts of this material differently, so the part may matter here."
        case .rulesetMayBeStale(let compiledOn, let months):
            "These rules were compiled \(compiledOn), about \(months) months ago. Municipal rules change."
        }
    }

    /// What would settle it.
    var remedy: String {
        switch self {
        case .materialNotRecognised:
            "Describe the part yourself to get a usable answer."
        case .noRuleForMaterial:
            "Usually fine. Check with your local service if the part is unusual."
        case .noRuleAtAll:
            "Worth checking with your local waste service."
        case .ruleIgnoresPart:
            "Check the city's own guidance for this specific part."
        case .rulesetMayBeStale:
            "Confirm against the source before relying on it."
        }
    }
}

/// How much of the answer to lean on, derived from the reasons rather than invented.
enum Certainty: Int, Comparable, Sendable {
    case low = 0
    case limited = 1
    case high = 2

    static func < (lhs: Certainty, rhs: Certainty) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .high: "Confident"
        case .limited: "Limited confidence"
        case .low: "Low confidence"
        }
    }

    var symbol: String {
        switch self {
        case .high: "checkmark.seal.fill"
        case .limited: "exclamationmark.circle"
        case .low: "questionmark.circle.fill"
        }
    }
}

extension BinVerdict {
    /// Derived, never stored: certainty is a function of the reasons, so the two can
    /// never drift apart.
    var certainty: Certainty {
        if uncertainty.contains(where: {
            if case .noRuleAtAll = $0 { return true }
            if case .materialNotRecognised = $0 { return true }
            return false
        }) {
            return .low
        }
        return uncertainty.isEmpty ? .high : .limited
    }
}

extension RulesEngine {
    /// Months after which a ruleset is worth re-checking. Chosen because municipal
    /// collection contracts and deposit schemes typically change on an annual cycle;
    /// a year-old ruleset is not wrong, but it is no longer evidence.
    static let stalenessMonths = 12

    /// Every reason this verdict deserves a second look.
    func uncertainty(
        for component: PackagingComponent,
        verdict: BinVerdict,
        now: Date = Date()
    ) -> [UncertaintyReason] {
        var reasons: [UncertaintyReason] = []

        // A material with no taxonomy entry and no parent is one nobody has described.
        let canonical = MaterialTaxonomy.canonical(component.material)
        if MaterialTaxonomy.ancestry(of: canonical).count == 1,
           !MaterialTaxonomy.isKnown(canonical) {
            reasons.append(.materialNotRecognised(canonical))
        }

        switch verdict.quality {
        case .cityDefault:
            reasons.append(.noRuleAtAll)
        case .inherited(let matched):
            reasons.append(.noRuleForMaterial(matched: matched))
        case .exactMaterial:
            // Matched the material but not the part. That only matters if this city
            // actually distinguishes parts for this material elsewhere — otherwise the
            // rule is simply written at the right level and there is nothing to flag.
            if cityNarrowsByShape(for: component.material) {
                reasons.append(.ruleIgnoresPart)
            }
        case .exactWithShape:
            break
        }

        if let months = monthsSinceCompiled(now: now), months >= Self.stalenessMonths {
            reasons.append(.rulesetMayBeStale(compiledOn: ruleset.compiledOn, monthsOld: months))
        }

        return reasons
    }

    /// True when this city narrows at least one rule by part for this material or any of
    /// its ancestors — evidence that the part can matter here.
    private func cityNarrowsByShape(for material: TaxonomyID) -> Bool {
        let ancestry = Set(MaterialTaxonomy.ancestry(of: material))
        return ruleset.rules.contains { rule in
            guard let shapes = rule.shapes, !shapes.isEmpty else { return false }
            return !Set(rule.materials).isDisjoint(with: ancestry)
        }
    }

    private func monthsSinceCompiled(now: Date) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let compiled = formatter.date(from: ruleset.compiledOn) else { return nil }
        return Calendar.current.dateComponents([.month], from: compiled, to: now).month
    }
}
