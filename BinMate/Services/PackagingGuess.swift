import Foundation

/// Turns a general-purpose image classification label into a guess at a packaging part.
///
/// This is deliberately a *suggestion* engine, not a classifier of waste. Apple's Vision
/// taxonomy knows what a bottle looks like; it does not know whether that bottle is PET
/// or glass, and it has no idea what the local rules are. So everything here produces a
/// starting point that the user confirms or edits, and the rules engine — which does know
/// the local rules — still makes the actual decision.
///
/// Matching is on whole tokens rather than substrings, because Vision identifiers are
/// snake_case and substring matching turns "candle" into a drinks can.
enum PackagingGuess {
    struct Suggestion: Hashable, Sendable {
        var shape: TaxonomyID
        var material: TaxonomyID
        /// The classifier's own confidence, carried through so the UI can order and
        /// visibly hedge on weak guesses.
        var confidence: Float
        /// The raw label this came from, shown to the user so the guess is explicable.
        var sourceLabel: String
        /// True when the material is implied by the shape rather than stated by the
        /// label — "a bottle is probably PET" — which is exactly the kind of assumption
        /// that deserves to be flagged rather than hidden.
        var materialIsAssumed: Bool

        /// How strongly to present this guess.
        ///
        /// Raw confidence is shown to nobody. Spread across a taxonomy of more than a
        /// thousand classes, a *correct* label commonly scores a few percent, so a
        /// literal "2% match" would read as broken while actually being a decent guess.
        /// The bands below are calibrated to that scale, not to intuition about
        /// percentages.
        var strength: Strength {
            switch confidence {
            case 0.15...: .likely
            case 0.03..<0.15: .possible
            default: .weak
            }
        }
    }

    enum Strength: Hashable, Sendable {
        case likely
        case possible
        case weak

        var label: String {
            switch self {
            case .likely: "likely"
            case .possible: "possible"
            case .weak: "long shot"
            }
        }
    }

    /// Shape keywords, most specific first.
    private static let shapeTokens: [(tokens: Set<String>, shape: TaxonomyID)] = [
        (["bottle"], "en:bottle"),
        (["jar"], "en:jar"),
        (["can", "tin"], "en:can"),
        (["carton"], "en:box"),
        (["box", "crate", "packet"], "en:box"),
        (["cup", "mug", "tumbler"], "en:tumbler"),
        (["bag", "sack", "pouch"], "en:bag"),
        (["tray", "plate", "dish"], "en:tray"),
        (["tub", "pot", "bowl", "container", "jug"], "en:pot"),
        (["lid", "cap", "cork", "stopper"], "en:lid"),
        (["wrapper", "wrapping", "foil", "film"], "en:wrapper"),
        (["straw"], "en:drinking-straw"),
        (["label", "sticker", "tag"], "en:label"),
    ]

    /// Material keywords that the label states outright.
    private static let materialTokens: [(tokens: Set<String>, material: TaxonomyID)] = [
        (["glass"], "en:clear-glass"),
        (["aluminum", "aluminium"], "en:aluminium"),
        (["foil"], "en:aluminium"),
        (["steel", "metal", "metallic"], "en:metal"),
        (["tin"], "en:tin-plated-steel"),
        (["cardboard", "corrugated"], "en:cardboard"),
        (["carton"], "en:paper-and-cardboard-plastic-aluminium"),
        (["paper", "papers"], "en:paper"),
        (["plastic", "polythene", "polyethylene"], "en:o-7-other-plastics"),
        (["wood", "wooden", "timber"], "en:wood"),
        (["cork"], "en:cork"),
    ]

    /// What a shape is usually made of when nothing says otherwise. Assumptions, and
    /// flagged as such in the UI.
    private static let assumedMaterial: [TaxonomyID: TaxonomyID] = [
        "en:bottle": "en:pet-1-polyethylene-terephthalate",
        "en:jar": "en:clear-glass",
        "en:can": "en:aluminium",
        "en:box": "en:cardboard",
        "en:tumbler": "en:o-7-other-plastics",
        "en:bag": "en:ldpe-4-low-density-polyethylene",
        "en:tray": "en:o-7-other-plastics",
        "en:pot": "en:o-7-other-plastics",
        "en:lid": "en:pp-5-polypropylene",
        "en:wrapper": "en:ldpe-4-low-density-polyethylene",
        "en:drinking-straw": "en:pp-5-polypropylene",
        "en:label": "en:paper",
    ]

    /// Drinks that come in glass often enough to override the bottle default.
    private static let glassBottleHints: Set<String> = ["wine", "beer", "champagne", "spirit", "whiskey"]

    /// Produces a suggestion for one classification label, or nil when the label has
    /// nothing to do with packaging — most of Vision's taxonomy is animals, plants and
    /// scenery, and guessing from those would be worse than saying nothing.
    static func suggestion(forLabel label: String, confidence: Float) -> Suggestion? {
        let tokens = Set(
            label.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
        )
        guard !tokens.isEmpty else { return nil }

        guard let shape = shapeTokens.first(where: { !$0.tokens.isDisjoint(with: tokens) })?.shape else {
            return nil
        }

        if let stated = materialTokens.first(where: { !$0.tokens.isDisjoint(with: tokens) })?.material {
            return Suggestion(
                shape: shape,
                material: stated,
                confidence: confidence,
                sourceLabel: label,
                materialIsAssumed: false
            )
        }

        if shape == "en:bottle", !glassBottleHints.isDisjoint(with: tokens) {
            return Suggestion(
                shape: shape,
                material: "en:clear-glass",
                confidence: confidence,
                sourceLabel: label,
                materialIsAssumed: true
            )
        }

        return Suggestion(
            shape: shape,
            material: assumedMaterial[shape] ?? "en:o-7-other-plastics",
            confidence: confidence,
            sourceLabel: label,
            materialIsAssumed: true
        )
    }

    /// Ranks labels into a short list of distinct parts.
    ///
    /// Collapsed by shape: a photo that scores "water_bottle", "bottle" and "pop_bottle"
    /// describes one bottle, not three, and offering three would be nonsense.
    static func suggestions(
        forLabels labels: [(label: String, confidence: Float)],
        limit: Int = 4
    ) -> [Suggestion] {
        var bestByShape: [TaxonomyID: Suggestion] = [:]

        for entry in labels {
            guard let candidate = suggestion(forLabel: entry.label, confidence: entry.confidence) else {
                continue
            }
            if let existing = bestByShape[candidate.shape] {
                // Prefer a stated material over an assumed one even at lower confidence:
                // "glass_bottle" at 0.3 beats "bottle" at 0.6, because it says more.
                let candidateWins = (existing.materialIsAssumed && !candidate.materialIsAssumed)
                    || (existing.materialIsAssumed == candidate.materialIsAssumed
                        && candidate.confidence > existing.confidence)
                if candidateWins { bestByShape[candidate.shape] = candidate }
            } else {
                bestByShape[candidate.shape] = candidate
            }
        }

        return bestByShape.values
            .sorted { $0.confidence > $1.confidence }
            .prefix(limit)
            .map { $0 }
    }

    /// The component a suggestion becomes once accepted.
    static func component(from suggestion: Suggestion) -> PackagingComponent {
        PackagingComponent(shape: suggestion.shape, material: suggestion.material)
    }
}
