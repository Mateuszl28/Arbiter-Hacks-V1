import Foundation

// Checks the Vision-label-to-packaging mapping. Pure logic, no Vision framework, so it
// runs in a second on the host and does not need a photo or a device.

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("  FAIL: \(message)")
    }
}

func guess(_ label: String, _ confidence: Float = 0.5) -> PackagingGuess.Suggestion? {
    PackagingGuess.suggestion(forLabel: label, confidence: confidence)
}

print("=== single labels ===")
for label in ["water_bottle", "glass_jar", "beverage_can", "cardboard_box", "plastic_bag", "wine_bottle"] {
    if let s = guess(label) {
        let assumed = s.materialIsAssumed ? " (material assumed)" : ""
        print("  \(label) -> \(ShapeTaxonomy.displayName(for: s.shape)) · \(MaterialTaxonomy.displayName(for: s.material))\(assumed)")
    } else {
        print("  \(label) -> no suggestion")
    }
}

print("\n--- assertions ---")

// 1. Shapes are recognised from snake_case identifiers.
check(guess("water_bottle")?.shape == "en:bottle", "water_bottle should be a bottle")
check(guess("beverage_can")?.shape == "en:can", "beverage_can should be a can")
check(guess("glass_jar")?.shape == "en:jar", "glass_jar should be a jar")

// 2. A stated material beats the shape's assumption, and is not flagged as assumed.
let glassJar = guess("glass_jar")
check(glassJar?.material == "en:clear-glass", "glass_jar material should be glass")
check(glassJar?.materialIsAssumed == false, "a stated material must not be flagged as assumed")

// 3. An unstated material falls back to the shape default, flagged honestly.
let plainBottle = guess("bottle")
check(plainBottle?.material == "en:pet-polyethylene-terephthalate", "a plain bottle should assume PET")
check(plainBottle?.materialIsAssumed == true, "an assumed material must be flagged")

// 4. Drink hints override the PET assumption — a wine bottle is not PET.
check(guess("wine_bottle")?.material == "en:clear-glass", "wine_bottle should assume glass, not PET")
check(guess("beer_bottle")?.material == "en:clear-glass", "beer_bottle should assume glass")

// 5. Token matching, not substring matching. This is the bug the design exists to avoid.
check(guess("candle") == nil, "'candle' must not be read as a can")
check(guess("candy") == nil, "'candy' must not be read as a can")
check(guess("canyon") == nil, "'canyon' must not be read as a can")
check(guess("toucan") == nil, "'toucan' must not be read as a can")

// 6. Most of Vision's taxonomy is not packaging and must produce nothing.
for label in ["golden_retriever", "mountain", "espresso", "person", "sunset", "violin"] {
    check(guess(label) == nil, "'\(label)' should produce no packaging suggestion")
}

// 7. Several labels describing one object collapse to one suggestion per shape.
let collapsed = PackagingGuess.suggestions(forLabels: [
    ("water_bottle", 0.62),
    ("bottle", 0.55),
    ("pop_bottle", 0.41),
])
check(collapsed.count == 1, "three bottle labels should collapse to one suggestion, got \(collapsed.count)")

// 8. A more informative label wins even at lower confidence.
let informative = PackagingGuess.suggestions(forLabels: [
    ("bottle", 0.90),
    ("glass_bottle", 0.30),
])
check(informative.count == 1, "should still be one bottle")
check(
    informative.first?.material == "en:clear-glass",
    "the label that states its material should win over a higher-confidence vague one"
)
check(informative.first?.materialIsAssumed == false, "the winning suggestion states its material")

// 9. Distinct shapes are kept and ordered by confidence.
let multi = PackagingGuess.suggestions(forLabels: [
    ("cardboard_box", 0.30),
    ("beverage_can", 0.80),
    ("plastic_bag", 0.50),
])
check(multi.count == 3, "three distinct shapes should all survive, got \(multi.count)")
check(multi.first?.shape == "en:can", "highest confidence should come first")

// 10. The limit is respected.
let many = PackagingGuess.suggestions(
    forLabels: [("bottle", 0.9), ("can", 0.8), ("box", 0.7), ("bag", 0.6), ("cup", 0.5)],
    limit: 2
)
check(many.count == 2, "limit should cap the result, got \(many.count)")

// 11. Strength bands are calibrated to Vision's actual scale, where a correct label in a
// 1300-class taxonomy routinely scores a few percent. A measured real example: a bottle
// recognised at 0.017 must not be presented as a dead certainty, nor hidden entirely.
check(guess("bottle", 0.40)?.strength == .likely, "0.40 should read as likely")
check(guess("bottle", 0.08)?.strength == .possible, "0.08 should read as possible")
check(guess("bottle", 0.017)?.strength == .weak, "0.017 should read as a long shot")
check(
    PackagingGuess.Strength.weak.label == "long shot",
    "the weakest band should be worded as a guess, not a percentage"
)

// 12. Suggestions must convert into components the rules engine can actually resolve.
let rulesBase = ProcessInfo.processInfo.environment["BINMATE_RULES"] ?? "BinMate/Resources/Rules"
let cityFiles = ["pl-krakow.json", "de-berlin.json", "us-san-francisco.json", "jp-tokyo-shibuya.json"]
let cities = try cityFiles.map {
    try JSONDecoder().decode(
        CityRuleset.self,
        from: Data(contentsOf: URL(fileURLWithPath: rulesBase + "/" + $0))
    )
}

print("\n=== every suggestion resolves in every city ===")
let everyShapeLabel = [
    "bottle", "jar", "can", "cardboard_box", "cup", "plastic_bag",
    "tray", "tub", "bottle_cap", "wrapper", "drinking_straw", "label",
]
for label in everyShapeLabel {
    guard let s = guess(label, 0.5) else {
        check(false, "'\(label)' should produce a suggestion")
        continue
    }
    let component = PackagingGuess.component(from: s)
    for city in cities {
        let verdict = RulesEngine(ruleset: city).verdict(for: component)
        check(
            verdict.stream.id != "unknown",
            "\(city.displayName): '\(label)' fell through to the placeholder stream"
        )
    }
}
print("  \(everyShapeLabel.count) shapes × \(cities.count) cities resolved")

print(failures == 0 ? "\nAll guess checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
