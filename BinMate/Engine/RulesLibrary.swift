import Foundation
import OSLog

/// Loads every city ruleset bundled with the app.
///
/// Discovery is by scanning rather than by a hard-coded list, so adding a city really is
/// a data change: drop a JSON file into `Resources/Rules` and it appears in the picker.
/// The cost of that convenience is that a malformed file could vanish silently, so files
/// that *look* like rulesets but fail to load are reported in `problems` instead of
/// being skipped quietly.
struct RulesLibrary: Sendable {
    /// Rulesets that loaded and validated, sorted by display name.
    let cities: [CityRuleset]
    /// Human-readable load failures, surfaced in Settings rather than swallowed.
    let problems: [String]

    private static let logger = Logger(subsystem: "app.binmate", category: "RulesLibrary")

    static func loadBundled(bundle: Bundle = .main) -> RulesLibrary {
        var cities: [CityRuleset] = []
        var problems: [String] = []

        let decoder = JSONDecoder()

        for url in candidateURLs(in: bundle) {
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                problems.append("\(name): could not be read")
                continue
            }
            // Only complain about files that were clearly meant to be rulesets.
            guard looksLikeRuleset(data) else { continue }

            do {
                let ruleset = try decoder.decode(CityRuleset.self, from: data)
                let issues = validate(ruleset)
                if issues.isEmpty {
                    cities.append(ruleset)
                } else {
                    problems.append("\(name): " + issues.joined(separator: "; "))
                }
            } catch {
                problems.append("\(name): \(error.localizedDescription)")
            }
        }

        if cities.isEmpty {
            problems.append("No city rulesets loaded — the app has nothing to sort against.")
            logger.error("No city rulesets loaded from bundle")
        }

        return RulesLibrary(
            cities: cities.sorted { $0.displayName < $1.displayName },
            problems: problems
        )
    }

    /// Looks in the `Rules` subdirectory and in the bundle root, because whether Xcode
    /// flattens a resource folder depends on how the target is configured.
    private static func candidateURLs(in bundle: Bundle) -> [URL] {
        let nested = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Rules") ?? []
        let root = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []

        var seen = Set<String>()
        return (nested + root).filter { seen.insert($0.lastPathComponent).inserted }
    }

    private static func looksLikeRuleset(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["streams"] != nil && object["rules"] != nil
    }

    /// Catches the mistakes hand-written JSON actually makes: a rule pointing at a
    /// stream id that was renamed, or a default stream that does not exist.
    private static func validate(_ ruleset: CityRuleset) -> [String] {
        var issues: [String] = []
        let streamIDs = Set(ruleset.streams.map(\.id))

        if streamIDs.count != ruleset.streams.count {
            issues.append("duplicate stream ids")
        }
        if !streamIDs.contains(ruleset.defaultStreamID) {
            issues.append("defaultStreamID '\(ruleset.defaultStreamID)' is not a defined stream")
        }
        for rule in ruleset.rules where !streamIDs.contains(rule.stream) {
            issues.append("rule for \(rule.materials.map(\.value).joined(separator: ", ")) points at unknown stream '\(rule.stream)'")
        }
        if ruleset.rules.isEmpty {
            issues.append("no rules defined")
        }
        for stream in ruleset.streams where stream.kind == .deposit && stream.depositAmount == nil {
            issues.append("deposit stream '\(stream.id)' has no depositAmount")
        }
        return issues
    }

    func city(id: String) -> CityRuleset? {
        cities.first { $0.id == id }
    }

    /// Used when the user has never chosen a city and nothing better is known.
    var fallbackCity: CityRuleset? { cities.first }
}
