import Foundation

/// Everything the app knows about the state of its own data, in one place.
///
/// The pieces already existed and were scattered: load failures in Settings, conflicts at
/// the foot of a rule book, coverage inside a city page, staleness inside a verdict. Each
/// was visible only to someone who happened to be looking at that screen. Collected here
/// they answer a question none of them could individually — *is this app's data in good
/// shape, and if not, what is worst?*
///
/// Reports only what it can substantiate. There is no overall score: a single number
/// would have to weight incommensurable things against each other, and the weighting
/// would be invented.
struct DataQuality: Sendable {
    enum Severity: Int, Comparable, Sendable {
        case info = 0
        case warning = 1
        case error = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Issue: Sendable, Identifiable, Hashable {
        var id: String { "\(area)|\(detail)" }
        var severity: Severity
        /// Which part of the data this is about, for grouping.
        var area: String
        var detail: String
        /// What would resolve it. Every issue must have one.
        var action: String
    }

    var issues: [Issue]
    /// Headline counts, so the panel can say how much was checked rather than only what
    /// was wrong. A clean report means nothing unless you know what was examined.
    var checked: (cities: Int, rules: Int, materials: Int, products: Int)

    var errors: [Issue] { issues.filter { $0.severity == .error } }
    var warnings: [Issue] { issues.filter { $0.severity == .warning } }

    static func assess(
        library: RulesLibrary,
        samples: SampleProducts,
        now: Date = Date()
    ) -> DataQuality {
        var issues: [Issue] = []

        // 1. Anything that failed to load at all.
        for problem in library.problems + samples.problems {
            issues.append(
                Issue(
                    severity: .error,
                    area: "Bundled data",
                    detail: problem,
                    action: "Fix the file and rebuild; the app is running without it."
                )
            )
        }

        // 2. Rules that contradict each other or can never fire.
        for city in library.cities {
            for finding in RuleConflicts.findings(in: city) {
                issues.append(
                    Issue(
                        severity: finding.severity == .error ? .error : .warning,
                        area: city.displayName,
                        detail: "Rule \(finding.ruleIndex + 1) \(finding.message)",
                        action: finding.severity == .error
                            ? "Reorder or merge the rules; one of them is currently dead."
                            : "Remove the redundant rule, or leave it if the duplication is deliberate."
                    )
                )
            }
        }

        // 3. Sources that have not been re-checked in a long time. Not wrong, but no
        //    longer evidence.
        for city in library.cities {
            guard let months = monthsSince(city.compiledOn, now: now),
                  months >= RulesEngine.stalenessMonths else { continue }
            issues.append(
                Issue(
                    severity: .warning,
                    area: city.displayName,
                    detail: "Compiled \(city.compiledOn), about \(months) months ago, from \(city.sourceName).",
                    action: "Re-check against the source and update compiledOn."
                )
            )
        }

        // 4. Where the rules are thin. Only the gaps that cost something are reported;
        //    listing every general rule would bury the ones that matter.
        let coverage = CoverageAnalysis.analyse(cities: library.cities)
        for gap in coverage.highPriority {
            issues.append(
                Issue(
                    severity: .warning,
                    area: gap.cityName,
                    detail: "\(MaterialTaxonomy.displayName(for: gap.material)) has \(gap.level.label).",
                    action: "Add a rule for it; it is a material people commonly hold."
                )
            )
        }

        // 5. Bundled product data that looks wrong before anyone sorts it.
        for product in samples.products {
            for anomaly in PackagingAnomalyDetector.anomalies(in: product) {
                issues.append(
                    Issue(
                        severity: anomaly.isLikelyError ? .error : .info,
                        area: product.name,
                        detail: anomaly.summary,
                        action: "Check the record against the physical packaging."
                    )
                )
            }
        }

        issues.sort {
            $0.severity == $1.severity ? $0.area < $1.area : $0.severity > $1.severity
        }

        return DataQuality(
            issues: issues,
            checked: (
                cities: library.cities.count,
                rules: library.cities.reduce(0) { $0 + $1.rules.count },
                materials: MaterialTaxonomy.pickerMaterials.count,
                products: samples.products.count
            )
        )
    }

    private static func monthsSince(_ compiledOn: String, now: Date) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: compiledOn) else { return nil }
        return Calendar.current.dateComponents([.month], from: date, to: now).month
    }
}
