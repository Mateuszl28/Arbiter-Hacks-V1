import Foundation

// A throwaway harness that exercises RulesEngine against the real bundled JSON,
// so the headline behaviour is verified rather than assumed.

func loadRuleset(_ path: String) throws -> CityRuleset {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(CityRuleset.self, from: data)
}

// Set by Tools/verify-rules.sh so the checks are not tied to one machine.
let base = (ProcessInfo.processInfo.environment["BINMATE_RULES"] ?? "BinMate/Resources/Rules")
    + "/"
let cities = try ["pl-krakow.json", "de-berlin.json", "us-san-francisco.json", "jp-tokyo-shibuya.json"].map {
    try loadRuleset(base + $0)
}

// A 500 ml PET drinks bottle: three parts, as it actually exists.
let bottle = ScannedProduct(
    barcode: "5449000000996",
    name: "Cola 500 ml",
    brand: "Demo",
    imageURL: nil,
    components: [
        PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate", quantityPerUnit: "24 g"),
        PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene"),
        PackagingComponent(shape: "en:label", material: "en:paper"),
    ],
    origin: .manual
)

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("  FAIL: \(message)")
    }
}

for city in cities {
    let engine = RulesEngine(ruleset: city)
    let verdicts = engine.verdicts(for: bottle)
    print("\n=== \(city.flag) \(city.displayName) — \(verdicts.destinationCount) destinations ===")
    for v in verdicts {
        let deposit = v.depositValue.map { " [+\($0) \(v.stream.depositCurrencyCode ?? "")]" } ?? ""
        print("  \(v.component.headline)")
        print("    -> \(v.stream.name) (\(v.stream.localName ?? "-"))\(deposit)  [\(v.quality.label)]")
        if let i = v.instruction { print("       \(i)") }
        if let c = v.caution { print("       ! \(c)") }
    }
}

print("\n--- assertions ---")

// 1. Ancestry fallback: PP cap has no PP rule anywhere, it must inherit the plastic rule.
let krakow = RulesEngine(ruleset: cities[0])
let cap = bottle.components[1]
let capVerdict = krakow.verdict(for: cap)
check(capVerdict.stream.id == "plastic-metal", "PP cap in Kraków should inherit the plastic rule")
if case .inherited(let from) = capVerdict.quality {
    check(from == "en:plastic", "cap should inherit from en:plastic, got \(from)")
} else {
    check(false, "cap match quality should be .inherited, got \(capVerdict.quality)")
}

// 2. Shape-specific rules must beat broader material rules.
let berlin = RulesEngine(ruleset: cities[1])
let bottleVerdict = berlin.verdict(for: bottle.components[0])
check(bottleVerdict.stream.id == "pfand", "PET bottle in Berlin must route to Pfand, not the yellow bin")
check(bottleVerdict.depositValue == Decimal(string: "0.25"), "Berlin PET bottle deposit should be 0.25")

// 3. ...but only for that shape. PET film must NOT get the deposit.
let film = PackagingComponent(shape: "en:film", material: "en:pet-polyethylene-terephthalate")
check(berlin.verdict(for: film).stream.id == "gelbe", "PET film in Berlin must go to the yellow bin, not Pfand")

// 4. The same material genuinely diverges across cities — the product's whole premise.
// Compostable plastic is the sharpest case: San Francisco composts it, the two
// European cities reject it from organic collection entirely.
let pla = PackagingComponent(shape: "en:cup", material: "en:pla-polylactic-acid")
let plaVerdicts = cities.map { RulesEngine(ruleset: $0).verdict(for: pla) }
check(plaVerdicts[0].stream.kind == .residual, "Kraków must not compost PLA")
check(plaVerdicts[1].stream.kind == .residual, "Berlin must not compost PLA")
check(plaVerdicts[2].stream.kind == .organic, "San Francisco must compost PLA")
check(plaVerdicts[3].stream.id == "burnable", "Tokyo should burn PLA")
check(Set(plaVerdicts.map(\.stream.id)).count == 4, "PLA should land in four distinct streams")
check(Set(plaVerdicts.compactMap(\.caution)).count == 4, "each city should give its own PLA caveat")
print("  PLA cup: " + cities.enumerated().map { i, c in
    "\(c.displayName)=\(RulesEngine(ruleset: c).verdict(for: pla).stream.name)"
}.joined(separator: ", "))

// 5. Instructions must actually contradict: Kraków says squash, Berlin says do not crush.
let krakowBottle = krakow.verdict(for: bottle.components[0])
check(krakowBottle.instruction?.contains("squash") == true, "Kraków should tell the user to squash the bottle")
check(bottleVerdict.caution?.lowercased().contains("do not crush") == true, "Berlin should warn against crushing")

// 6. An unknown material must fall back to the city default, not disappear.
let mystery = PackagingComponent(material: "en:moon-rock")
let mysteryVerdict = krakow.verdict(for: mystery)
check(mysteryVerdict.quality == .cityDefault, "unknown material should hit the city default")
check(mysteryVerdict.stream.id == "mixed", "Kraków default should be mixed waste")

// 7. Contributed spelling variants must normalise onto the taxonomy.
check(MaterialTaxonomy.canonical("PET") == "en:pet-polyethylene-terephthalate", "'PET' should canonicalise")
check(MaterialTaxonomy.canonical(" Aluminum ") == "en:aluminium", "'Aluminum' should canonicalise")
check(TaxonomyID("en:Bottle") == TaxonomyID("bottle"), "shape ids should normalise case and prefix")

// 8. Multipack deposits must multiply.
let sixPack = PackagingComponent(shape: "en:can", material: "en:aluminium", numberOfUnits: 6)
check(berlin.verdict(for: sixPack).depositValue == Decimal(string: "1.50"), "six cans in Berlin should total 1.50")

// 9. Grouping should collapse same-stream parts.
check(krakow.verdicts(for: bottle).groupedByStream.count == 2, "Kraków should group the bottle into 2 destinations")

// 10. Tokyo sorts by burnability rather than purely by material, which is a different
// model from the European bin systems. The schema has to express it without special
// cases: the same material must split by shape in both directions.
let tokyo = RulesEngine(ruleset: cities[3])
let tokyoBottle = tokyo.verdict(for: bottle.components[0])
check(tokyoBottle.stream.id == "pet-bottles", "Tokyo PET bottle should be its own resource stream")
check(
    tokyoBottle.instruction?.lowercased().contains("label") == true,
    "Tokyo must tell the user to remove the label — no other city does"
)
// A PET bottle is a resource; a PET tray is container packaging; loose PET is burned.
check(
    tokyo.verdict(for: PackagingComponent(shape: "en:tray", material: "en:pet-polyethylene-terephthalate")).stream.id == "plastic-packaging",
    "Tokyo PET tray should be plastic packaging, not a PET bottle resource"
)
check(
    tokyo.verdict(for: PackagingComponent(material: "en:other-plastics")).stream.id == "burnable",
    "Tokyo non-container plastic should be burnable"
)
// Glass splits by shape too: bottles are a resource, everything else is non-burnable.
check(
    tokyo.verdict(for: PackagingComponent(shape: "en:jar", material: "en:clear-glass")).stream.id == "cans-glass",
    "Tokyo glass jar should be a resource"
)
check(
    tokyo.verdict(for: PackagingComponent(shape: "en:tray", material: "en:clear-glass")).stream.id == "non-burnable",
    "Tokyo non-bottle glass should be non-burnable"
)

// 11. Four cities, four different instructions for one PET bottle. This is the claim the
// whole product rests on, so it is asserted rather than asserted in a README.
let bottleInstructions = cities.map {
    RulesEngine(ruleset: $0).verdict(for: bottle.components[0]).instruction ?? ""
}
check(
    Set(bottleInstructions).count == 4,
    "all four cities should give a distinct instruction for the same PET bottle"
)
print("  PET bottle instructions:")
for (city, instruction) in zip(cities, bottleInstructions) {
    print("    \(city.flag) \(city.displayName): \(instruction)")
}

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) assertion(s) FAILED.")
exit(failures == 0 ? 0 : 1)
