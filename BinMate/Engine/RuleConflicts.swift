import Foundation

/// Finds rules that contradict each other, or that can never fire.
///
/// The whole design rests on cities being data: adding one is a JSON file, not a code
/// change. That is only an advantage if the data can be checked. A rule written in good
/// faith can still be dead — shadowed by a broader rule listed above it — and nothing in
/// the app would ever say so. The verdict would simply be quietly wrong, with a
/// confident explanation attached.
///
/// Deliberately not a linter over style. Every finding here is something that changes an
/// answer a user gets.
enum RuleConflicts {
    enum Severity: String, Sendable {
        /// Changes an answer, or makes a rule meaningless.
        case error
        /// Worth a second look, but defensible.
        case warning
    }

    struct Finding: Sendable, Hashable {
        var severity: Severity
        var ruleIndex: Int
        var message: String
    }

    /// Checks one city.
    static func findings(in ruleset: CityRuleset) -> [Finding] {
        var findings: [Finding] = []
        let rules = ruleset.rules

        for (index, rule) in rules.enumerated() {
            // A rule listing the same material twice is harmless but suggests a copy
            // that was meant to be edited.
            let duplicated = Dictionary(grouping: rule.materials, by: { $0 })
                .filter { $0.value.count > 1 }
                .keys
            for material in duplicated {
                findings.append(
                    Finding(
                        severity: .warning,
                        ruleIndex: index,
                        message: "lists \(MaterialTaxonomy.displayName(for: material)) more than once"
                    )
                )
            }

            if rule.materials.isEmpty {
                findings.append(
                    Finding(severity: .error, ruleIndex: index, message: "names no material, so it can never fire")
                )
            }

            if rule.shapes?.isEmpty == true {
                findings.append(
                    Finding(
                        severity: .warning,
                        ruleIndex: index,
                        message: "has an empty shapes list; omit the key instead, or it reads as a narrowing that narrows nothing"
                    )
                )
            }

            // The important one: is this rule reachable at all?
            for material in rule.materials {
                guard let shadow = shadowingRule(for: material, shapes: rule.shapes, before: index, in: rules) else {
                    continue
                }
                // Same destination is redundant rather than wrong.
                let severity: Severity = rules[shadow].stream == rule.stream ? .warning : .error
                let verb = severity == .error ? "is unreachable" : "is redundant"
                findings.append(
                    Finding(
                        severity: severity,
                        ruleIndex: index,
                        message: "\(verb) for \(MaterialTaxonomy.displayName(for: material)): rule \(shadow + 1) matches it first"
                            + (severity == .error ? " and sends it to '\(rules[shadow].stream)' instead of '\(rule.stream)'" : "")
                    )
                )
            }
        }

        return findings
    }

    /// The rule the engine would actually pick for this material and shape set, if it
    /// comes earlier in the file.
    ///
    /// Mirrors `RulesEngine.bestMatch`: nearest ancestry level first, shape-specific
    /// before general. A rule is only shadowed if an earlier one wins at the *same or
    /// nearer* level — a broader ancestor rule never beats a specific one, whatever the
    /// order in the file.
    private static func shadowingRule(
        for material: TaxonomyID,
        shapes: [TaxonomyID]?,
        before index: Int,
        in rules: [BinRule]
    ) -> Int? {
        for (other, candidate) in rules.enumerated() where other < index {
            guard candidate.materials.contains(material) else { continue }

            switch (candidate.shapes, shapes) {
            case (nil, _), (.some([]), _):
                // An earlier rule with no shape narrowing catches everything this one
                // would have caught.
                return other
            case (.some(let earlier), .some(let mine)):
                // Only shadowed if the earlier rule covers every shape this one claims.
                if !mine.isEmpty, Set(mine).isSubset(of: Set(earlier)) { return other }
            case (.some, nil):
                // An earlier shape-specific rule cannot shadow a general one.
                continue
            }
        }
        return nil
    }
}
