import Foundation

/// Where each city's ruleset is thin, and which gap is worth filling first.
///
/// The bottleneck on this project is not code, it is research per city. That makes it
/// worth knowing which missing rule actually costs something. A city with no rule for
/// PET bottles is a serious gap; one with no rule for cork is a footnote. Counting gaps
/// without weighting them would point the work at whatever happens to be alphabetically
/// first.
struct CoverageAnalysis: Sendable {
    enum Level: Int, Comparable, Sendable {
        /// No rule anywhere in the material's ancestry. Falls to the catch-all bin.
        case none = 0
        /// Only a broader ancestor rule applies.
        case inherited = 1
        /// A rule names this material.
        case specific = 2

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .none: "no rule"
            case .inherited: "general rule"
            case .specific: "specific rule"
            }
        }
    }

    struct Gap: Sendable, Identifiable {
        var id: String { "\(cityID)|\(material.value)" }
        var cityID: String
        var cityName: String
        var material: TaxonomyID
        var level: Level
        /// Lower is more urgent.
        var rank: Int

        var priority: String {
            switch (level, rank) {
            case (.none, ..<6): "high"
            case (.none, _): "medium"
            case (.inherited, ..<6): "medium"
            default: "low"
            }
        }

        var summary: String {
            "\(MaterialTaxonomy.displayName(for: material)) in \(cityName): \(level.label)"
        }
    }

    var gaps: [Gap]
    /// Coverage per city, for the headline figure.
    var byCity: [(cityID: String, cityName: String, specific: Int, inherited: Int, missing: Int)]

    /// Analyses every bundled city against the materials the app can actually produce.
    ///
    /// Scoped to `pickerMaterials` deliberately: those are the materials a user can
    /// choose or a photo can suggest, so a gap there is reachable. Reporting gaps for
    /// taxonomy entries nothing can produce would be noise.
    static func analyse(cities: [CityRuleset]) -> CoverageAnalysis {
        var gaps: [Gap] = []
        var byCity: [(String, String, Int, Int, Int)] = []

        for city in cities {
            let engine = RulesEngine(ruleset: city)
            var specific = 0, inherited = 0, missing = 0

            for (rank, material) in MaterialTaxonomy.pickerMaterials.enumerated() {
                let verdict = engine.verdict(for: PackagingComponent(material: material))
                let level: Level

                switch verdict.quality {
                case .exactWithShape, .exactMaterial:
                    level = .specific
                    specific += 1
                case .inherited:
                    level = .inherited
                    inherited += 1
                case .cityDefault:
                    level = .none
                    missing += 1
                }

                if level != .specific {
                    gaps.append(
                        Gap(
                            cityID: city.id,
                            cityName: city.displayName,
                            material: material,
                            level: level,
                            // pickerMaterials is ordered by how often household packaging
                            // actually uses them, so position is a usable proxy for how
                            // much a gap costs.
                            rank: rank
                        )
                    )
                }
            }
            byCity.append((city.id, city.displayName, specific, inherited, missing))
        }

        // Worst level first, then commonest material, then alphabetical so the order is
        // stable between runs.
        gaps.sort {
            if $0.level != $1.level { return $0.level < $1.level }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.cityName < $1.cityName
        }

        return CoverageAnalysis(gaps: gaps, byCity: byCity)
    }

    var highPriority: [Gap] { gaps.filter { $0.priority == "high" } }
}
