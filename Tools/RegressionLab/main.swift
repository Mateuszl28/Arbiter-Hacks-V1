import Foundation

// Records what every known case resolves to, and refuses to let that change quietly.
//
// Rules are data, which is the design's strength and its exposure: editing one line of
// JSON can silently change answers for materials nobody was thinking about. Adding a
// `[en:plastic] -> yellow bin` rule above an existing one re-routes every plastic in the
// city, and the only symptom is that users start being told something different.
//
// So every case is resolved against a recorded baseline and the differences are printed.
// A change is not a failure — most are intended. The failure is *not knowing*.
//
//   ./Tools/verify-regression.sh          # compare against the baseline
//   ./Tools/record-regression.sh          # re-record it, after reviewing the diff

struct Case: Codable, Hashable {
    var city: String
    var material: String
    var shape: String?
    var stream: String
    var quality: String
    var certainty: String

    var key: String { "\(city)|\(material)|\(shape ?? "-")" }
    var describedCase: String {
        "\(city) · \(MaterialTaxonomy.displayName(for: TaxonomyID(material)))"
            + (shape.map { " · \(ShapeTaxonomy.displayName(for: TaxonomyID($0)))" } ?? "")
    }
}

let rulesBase = ProcessInfo.processInfo.environment["BINMATE_RULES"] ?? "Shared/Rules"
let baselinePath = ProcessInfo.processInfo.environment["BINMATE_BASELINE"]
    ?? "Tools/Fixtures/regression-baseline.json"
let recording = ProcessInfo.processInfo.environment["BINMATE_RECORD"] == "1"

let cityFiles = try FileManager.default.contentsOfDirectory(atPath: rulesBase)
    .filter { $0.hasSuffix(".json") }
    .sorted()
let cities = try cityFiles.map {
    try JSONDecoder().decode(
        CityRuleset.self,
        from: Data(contentsOf: URL(fileURLWithPath: "\(rulesBase)/\($0)"))
    )
}

// Shapes chosen to exercise the narrowing rules that actually exist across the rulesets:
// bottles and cans carry deposits, film and bags are refused at the kerb in some cities,
// caps and labels are the parts people forget.
let shapes: [TaxonomyID?] = [
    nil, "en:bottle", "en:can", "en:jar", "en:lid-or-cap",
    "en:label", "en:film", "en:bag", "en:box", "en:pot",
]

func describe(_ quality: MatchQuality) -> String {
    switch quality {
    case .exactWithShape: "exactWithShape"
    case .exactMaterial: "exactMaterial"
    case .inherited(let from): "inherited(\(from.value))"
    case .cityDefault: "cityDefault"
    }
}

func describe(_ certainty: Certainty) -> String {
    switch certainty {
    case .high: "high"
    case .limited: "limited"
    case .low: "low"
    }
}

var current: [Case] = []
for city in cities {
    let engine = RulesEngine(ruleset: city)
    for material in MaterialTaxonomy.pickerMaterials {
        for shape in shapes {
            let verdict = engine.verdict(
                for: PackagingComponent(shape: shape, material: material)
            )
            current.append(
                Case(
                    city: city.id,
                    material: material.value,
                    shape: shape?.value,
                    stream: verdict.stream.id,
                    quality: describe(verdict.quality),
                    certainty: describe(verdict.certainty)
                )
            )
        }
    }
}
current.sort { $0.key < $1.key }

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

if recording {
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: baselinePath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try encoder.encode(current).write(to: URL(fileURLWithPath: baselinePath))
    print("Recorded \(current.count) cases across \(cities.count) cities to \(baselinePath)")
    exit(0)
}

guard let data = try? Data(contentsOf: URL(fileURLWithPath: baselinePath)),
      let baseline = try? JSONDecoder().decode([Case].self, from: data) else {
    print("No baseline at \(baselinePath). Record one with ./Tools/record-regression.sh")
    exit(1)
}

let baselineByKey = Dictionary(uniqueKeysWithValues: baseline.map { ($0.key, $0) })
let currentByKey = Dictionary(uniqueKeysWithValues: current.map { ($0.key, $0) })

var changed: [(before: Case, after: Case)] = []
var added: [Case] = []
var removed: [Case] = []

for item in current {
    guard let before = baselineByKey[item.key] else {
        added.append(item)
        continue
    }
    if before != item { changed.append((before, item)) }
}
for item in baseline where currentByKey[item.key] == nil {
    removed.append(item)
}

print("Regression over \(current.count) cases in \(cities.count) cities")
print("  unchanged: \(current.count - changed.count - added.count)")
print("  changed:   \(changed.count)")
print("  new:       \(added.count)")
print("  gone:      \(removed.count)")

// A changed destination is the serious one: somebody is now being told to put an object
// somewhere else. A changed certainty is worth seeing but does not move any rubbish.
let movedBins = changed.filter { $0.before.stream != $0.after.stream }

if !changed.isEmpty {
    print("\nChanged:")
    for (before, after) in changed.prefix(40) {
        var parts: [String] = []
        if before.stream != after.stream { parts.append("bin \(before.stream) → \(after.stream)") }
        if before.quality != after.quality { parts.append("match \(before.quality) → \(after.quality)") }
        if before.certainty != after.certainty { parts.append("certainty \(before.certainty) → \(after.certainty)") }
        print("  \(before.describedCase): \(parts.joined(separator: ", "))")
    }
    if changed.count > 40 { print("  …and \(changed.count - 40) more") }
}
for item in added.prefix(10) { print("  new: \(item.describedCase) → \(item.stream)") }
if added.count > 10 { print("  …and \(added.count - 10) more new cases") }
for item in removed.prefix(10) { print("  gone: \(item.describedCase)") }

if movedBins.isEmpty && changed.isEmpty && added.isEmpty && removed.isEmpty {
    print("\nNo change. Every known case resolves exactly as recorded.")
    exit(0)
}

if !movedBins.isEmpty {
    print("\n\(movedBins.count) case(s) now go to a different bin.")
    print("Review them, then re-record with ./Tools/record-regression.sh if intended.")
    exit(1)
}

print("\nNo bin changed. Re-record with ./Tools/record-regression.sh to accept.")
exit(1)
