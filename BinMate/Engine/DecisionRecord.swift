import Foundation

/// What the engine decided at the moment of a scan, frozen.
///
/// Everything else in this project recomputes: switch city and the verdict re-resolves,
/// edit a rule and every answer changes. That is the right default, and it has one
/// consequence — history quietly rewrites itself. A scan from last spring is displayed
/// against today's rules, so a user who remembers being told something different has no
/// way to show it, and neither has the app.
///
/// Recording the decision makes history an account of what was actually said, and makes
/// one more question answerable: *would today's rules say the same thing?*
struct RecordedDecision: Codable, Hashable, Sendable {
    /// "Bottle · PET plastic", as shown at the time.
    var componentHeadline: String
    var material: String
    var shape: String?
    var streamID: String
    var streamName: String
    /// How the rule was matched, as a stable string rather than the enum — the enum may
    /// gain cases, and a record written today must still decode in a year.
    var quality: String
    var certainty: String
    /// Position of the rule that fired, if one did.
    var ruleIndex: Int?
    var cityID: String
    var compiledOn: String
    var sourceName: String

    init(verdict: BinVerdict, cityID: String) {
        self.componentHeadline = verdict.component.headline
        self.material = verdict.component.material.value
        self.shape = verdict.component.shape?.value
        self.streamID = verdict.stream.id
        self.streamName = verdict.stream.name
        self.quality = Self.describe(verdict.quality)
        self.certainty = Self.describe(verdict.certainty)
        self.ruleIndex = verdict.explanation.ruleIndex
        self.cityID = cityID
        self.compiledOn = verdict.explanation.compiledOn
        self.sourceName = verdict.explanation.sourceName
    }

    static func describe(_ quality: MatchQuality) -> String {
        switch quality {
        case .exactWithShape: "exactWithShape"
        case .exactMaterial: "exactMaterial"
        case .inherited(let from): "inherited(\(from.value))"
        case .cityDefault: "cityDefault"
        }
    }

    static func describe(_ certainty: Certainty) -> String {
        switch certainty {
        case .high: "high"
        case .limited: "limited"
        case .low: "low"
        }
    }
}

/// Re-runs a recorded decision against today's rules.
///
/// This is the regression lab pointed at one person's own history rather than at a test
/// corpus: if a ruleset has been corrected since, the scans it affected are exactly the
/// ones worth telling them about.
enum DecisionReview {
    struct Difference: Sendable, Hashable, Identifiable {
        var id: String { componentHeadline }
        var componentHeadline: String
        var wasStream: String
        var nowStream: String
        /// True when only the confidence or the matching changed, not the destination.
        var sameBin: Bool

        var summary: String {
            sameBin
                ? "\(componentHeadline): same bin, but the rules behind it changed"
                : "\(componentHeadline): was \(wasStream), now \(nowStream)"
        }
    }

    enum Outcome: Sendable, Equatable {
        /// No decision was recorded — a scan from before this existed.
        case notRecorded
        /// The ruleset it was decided under is no longer bundled.
        case rulesetGone(cityID: String)
        /// Today's rules agree.
        case unchanged
        /// Today's rules would answer differently.
        case changed([Difference])

        var movesABin: Bool {
            if case .changed(let differences) = self {
                return differences.contains { !$0.sameBin }
            }
            return false
        }
    }

    static func review(
        recorded: [RecordedDecision],
        product: ScannedProduct,
        library: RulesLibrary
    ) -> Outcome {
        guard !recorded.isEmpty else { return .notRecorded }
        guard let cityID = recorded.first?.cityID else { return .notRecorded }
        guard let ruleset = library.city(id: cityID) else { return .rulesetGone(cityID: cityID) }

        let engine = RulesEngine(ruleset: ruleset)
        let today = engine.verdicts(for: product)

        // Match on the component's own description: positions can shift if the user
        // corrected the parts, and comparing by index would invent differences.
        var byHeadline: [String: BinVerdict] = [:]
        for verdict in today { byHeadline[verdict.component.headline] = verdict }

        var differences: [Difference] = []
        for entry in recorded {
            guard let now = byHeadline[entry.componentHeadline] else { continue }

            let sameStream = now.stream.id == entry.streamID
            let sameReasoning = RecordedDecision.describe(now.quality) == entry.quality

            if !sameStream || !sameReasoning {
                differences.append(
                    Difference(
                        componentHeadline: entry.componentHeadline,
                        wasStream: entry.streamName,
                        nowStream: now.stream.name,
                        sameBin: sameStream
                    )
                )
            }
        }

        return differences.isEmpty ? .unchanged : .changed(differences)
    }
}
