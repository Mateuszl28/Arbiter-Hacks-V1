import Foundation

/// Checks BinMate's taxonomy against the published one it is derived from.
///
/// This suite exists because of a specific failure. The material tree was hand written,
/// and the identifiers in it were plausible rather than real: `en:pp-polypropylene` for
/// polypropylene, where the published entry is `en:pp-5-polypropylene`. Seven of those
/// covered the seven standard plastics, so every plastic with good data matched nothing
/// and went to residual waste — confidently, with an explanation attached.
///
/// Two assertions would have caught it on the day it was written:
///
///   1. Everything the published taxonomy can return must resolve to something here.
///   2. Nothing here may point at an identifier the published taxonomy does not contain,
///      unless it is declared as an extension of our own.
///
/// Both run below, against the vendored snapshot in Tools/Fixtures.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("  FAIL: \(message)")
        failures += 1
    }
}

func loadSnapshot(_ variable: String) -> [String: Any] {
    guard let path = ProcessInfo.processInfo.environment[variable],
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("  FAIL: could not read \(variable)")
        failures += 1
        return [:]
    }
    return parsed
}

let materialSnapshot = loadSnapshot("BINMATE_MATERIALS_SNAPSHOT")
let shapeSnapshot = loadSnapshot("BINMATE_SHAPES_SNAPSHOT")

// 1. Everything the taxonomy can hand us must land somewhere.
print("--- every published material resolves ---")
var unplaceable: [String] = []
for key in materialSnapshot.keys where !MaterialTaxonomy.isKnown(TaxonomyID(key)) {
    unplaceable.append(key)
}
check(
    unplaceable.isEmpty,
    "\(unplaceable.count) published materials cannot be placed: \(unplaceable.sorted().prefix(8).joined(separator: ", "))"
)
print("  \(materialSnapshot.count - unplaceable.count)/\(materialSnapshot.count) materials place")

print("\n--- every published shape resolves ---")
var unplaceableShapes: [String] = []
for key in shapeSnapshot.keys {
    let resolved = ShapeTaxonomy.canonical(TaxonomyID(key))
    if ShapeTaxonomy.displayName(for: resolved) == resolved.humanized && OFFTaxonomy.shapeNames[resolved] == nil {
        unplaceableShapes.append(key)
    }
}
check(
    unplaceableShapes.isEmpty,
    "\(unplaceableShapes.count) published shapes cannot be named: \(unplaceableShapes.sorted().prefix(8).joined(separator: ", "))"
)
print("  \(shapeSnapshot.count - unplaceableShapes.count)/\(shapeSnapshot.count) shapes name")

// 2. Nothing hand written may point at an identifier that does not exist upstream. This
//    is the assertion that was missing, and it is the one that matters: it is cheap to
//    write a convincing identifier and expensive to notice you did.
print("\n--- no hand written identifier is invented ---")
let declaredExtensions = Set(MaterialTaxonomy.declaredExtensions.map(\.value))
var invented: [String] = []
for target in MaterialTaxonomy.declaredTargets {
    let id = target.value
    if materialSnapshot[id] == nil && !declaredExtensions.contains(id) {
        invented.append(id)
    }
}
check(
    invented.isEmpty,
    "\(invented.count) hand written material identifiers are not in the published taxonomy: \(Set(invented).sorted().joined(separator: ", "))"
)

let shapeExtensions = Set(ShapeTaxonomy.declaredExtensions.map(\.value))
var inventedShapes: [String] = []
for target in ShapeTaxonomy.declaredTargets
where shapeSnapshot[target.value] == nil && !shapeExtensions.contains(target.value) {
    inventedShapes.append(target.value)
}
check(
    inventedShapes.isEmpty,
    "\(inventedShapes.count) hand written shape identifiers are not in the published taxonomy: \(Set(inventedShapes).sorted().joined(separator: ", "))"
)
print("  \(MaterialTaxonomy.declaredTargets.count) material and \(ShapeTaxonomy.declaredTargets.count) shape references checked against the source")

// 3. The ancestry walk has to reach the concepts cities actually write rules about,
//    otherwise placing a material is a formality that changes no verdict.
print("\n--- published materials reach a concept rules are written for ---")
let ruleBearing: Set<TaxonomyID> = [
    "en:plastic", "en:paper-or-cardboard", "en:glass", "en:metal",
    "en:composite-material", "en:wood",
]
var stranded: [String] = []
for key in materialSnapshot.keys {
    let ancestry = Set(MaterialTaxonomy.ancestry(of: TaxonomyID(key)))
    if ancestry.isDisjoint(with: ruleBearing) { stranded.append(key) }
}
let reached = materialSnapshot.count - stranded.count
print("  \(reached)/\(materialSnapshot.count) reach one of: \(ruleBearing.map(\.value).sorted().joined(separator: ", "))")
print("  \(stranded.count) do not, and they are listed rather than hidden:")
for key in stranded.sorted() {
    print("     \(key) — \(MaterialTaxonomy.displayName(for: TaxonomyID(key)))")
}

// 4. The city rules are hand written data too, and nobody had ever checked the
//    identifiers in them against the source. Three were invented — `en:cap`, `en:cup`
//    and `en:napkin` — and two of those sat in Tokyo's plastic packaging rule, keyed to
//    a shape no scan can produce. A rule that cannot fire is indistinguishable from a
//    rule that does not exist.
print("\n--- every identifier the city rules name exists upstream ---")

let rulesBase = (ProcessInfo.processInfo.environment["BINMATE_RULES"] ?? "Shared/Rules") + "/"
let rulesetFiles = [
    "pl-krakow.json", "de-berlin.json", "us-san-francisco.json",
    "jp-tokyo-shibuya.json", "us-new-york-city.json",
]
var ruleMaterials: Set<String> = []
var ruleShapes: Set<String> = []

for file in rulesetFiles {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: rulesBase + file)),
          let ruleset = try? JSONDecoder().decode(CityRuleset.self, from: data) else {
        check(false, "could not read \(file)")
        continue
    }
    for rule in ruleset.rules {
        for material in rule.materials { ruleMaterials.insert(material.value) }
        for shape in rule.shapes ?? [] { ruleShapes.insert(shape.value) }
    }
}

let inventedRuleMaterials = ruleMaterials
    .filter { materialSnapshot[$0] == nil && !declaredExtensions.contains($0) }
let inventedRuleShapes = ruleShapes
    .filter { shapeSnapshot[$0] == nil && !shapeExtensions.contains($0) }

check(
    inventedRuleMaterials.isEmpty,
    "city rules name \(inventedRuleMaterials.count) material(s) that do not exist: \(inventedRuleMaterials.sorted().joined(separator: ", "))"
)
check(
    inventedRuleShapes.isEmpty,
    "city rules name \(inventedRuleShapes.count) shape(s) that do not exist: \(inventedRuleShapes.sorted().joined(separator: ", "))"
)
print("  \(ruleMaterials.count) materials and \(ruleShapes.count) shapes named across \(rulesetFiles.count) cities, all present")

// 5. The folding has to agree with Tools/generate-taxonomy.py, which built the synonym
//    table. If the two drift, every non-English term stops resolving silently.
print("\n--- folding agrees with the generator ---")
let folds: [(String, String)] = [
    ("fr:PP 5 - Polypropylène", "pp-5-polypropylene"),
    ("es:Plástico", "plastico"),
    ("es:Cartón no ondulado", "carton-no-ondulado"),
    ("de:Wickler", "wickler"),
    ("xx:82-c-pap", "82-c-pap"),
]
for (raw, expected) in folds {
    check(TaxonomyID(raw).folded == expected, "\(raw) should fold to \(expected), got \(TaxonomyID(raw).folded)")
}
print("  \(folds.count) folds match")

print("\n--- synonym table ---")
check(OFFSynonyms.shared.materialCount > 1000, "the synonym table should have loaded, got \(OFFSynonyms.shared.materialCount) materials")
print("  \(OFFSynonyms.shared.materialCount) material and \(OFFSynonyms.shared.shapeCount) shape names, in every language the taxonomy records")

print(failures == 0 ? "\nAll taxonomy checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
