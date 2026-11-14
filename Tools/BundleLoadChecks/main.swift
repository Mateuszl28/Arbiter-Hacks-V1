import Foundation

// Loads the real built .app bundle and checks that every piece of bundled data is
// discoverable and valid. This exercises the riskiest path in the app — Xcode flattens
// resource folders, so the loaders must cope with a layout nobody wrote by hand.
//
// Run via Tools/verify-bundle.sh after a build.

let appPath = ProcessInfo.processInfo.environment["BINMATE_APP"]
    ?? "build/Debug-iphonesimulator/BinMate.app"

guard let bundle = Bundle(path: appPath) else {
    print("FAIL: no bundle at \(appPath) — build the app first")
    exit(1)
}

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("  FAIL: \(message)")
    }
}

print("Bundle: \(appPath)")

// MARK: - Rulesets

let library = RulesLibrary.loadBundled(bundle: bundle)

print("\nCities loaded: \(library.cities.count)")
for city in library.cities {
    print("  \(city.flag) \(city.displayName) — \(city.streams.count) streams, \(city.rules.count) rules")
}
if !library.problems.isEmpty {
    print("Problems reported:")
    for problem in library.problems { print("  - \(problem)") }
}

check(library.cities.count == 4, "expected 4 cities, got \(library.cities.count)")
check(library.problems.isEmpty, "ruleset loading should report no problems")
for expected in ["pl-krakow", "de-berlin", "us-san-francisco", "jp-tokyo-shibuya"] {
    check(library.city(id: expected) != nil, "\(expected) ruleset should load")
}

// DemoProducts.json sits in the same flattened directory and must not be mistaken for
// a ruleset, nor reported as a broken one.
check(
    !library.problems.contains { $0.contains("DemoProducts") },
    "DemoProducts.json must not be treated as a ruleset"
)

// MARK: - Sample products

let samples = SampleProducts.loadBundled(bundle: bundle)

print("\nSample products: \(samples.products.count)")
for product in samples.products {
    print("  \(product.name) — \(product.components.count) parts")
}
if !samples.problems.isEmpty {
    print("Problems reported:")
    for problem in samples.problems { print("  - \(problem)") }
}

check(samples.products.count == 5, "expected 5 sample products, got \(samples.products.count)")
check(samples.problems.isEmpty, "sample loading should report no problems")
check(
    samples.products.allSatisfy { !$0.components.isEmpty },
    "every sample product must have at least one packaging component"
)
check(
    samples.products.allSatisfy { $0.origin == .offlineSample },
    "bundled products must be labelled as offline samples"
)
check(samples.product(barcode: "5449000000996") != nil, "sample lookup by barcode should work")

// MARK: - Every sample resolves in every city

print("\nResolving every sample in every city:")
for city in library.cities {
    let engine = RulesEngine(ruleset: city)
    for product in samples.products {
        let verdicts = engine.verdicts(for: product)
        check(
            verdicts.count == product.components.count,
            "\(city.displayName)/\(product.name): expected \(product.components.count) verdicts, got \(verdicts.count)"
        )
        // Every component must land somewhere real, never the engine's last-resort stub.
        check(
            verdicts.allSatisfy { $0.stream.id != "unknown" },
            "\(city.displayName)/\(product.name): a component fell through to the placeholder stream"
        )
    }
    let unmatched = samples.products
        .flatMap { engine.verdicts(for: $0) }
        .filter { $0.quality == .cityDefault }
    print("  \(city.flag) \(city.displayName): \(unmatched.count) part(s) with no specific rule")
}

// MARK: - Siri / Shortcuts answers

// BinLookup is what Siri and Shortcuts call. It reads the same bundled rules and the same
// stored city as the app, so a spoken answer can never disagree with the screen.

print("\nSiri answers:")

let lookup = BinLookup(library: library)
let scratchDefaults = UserDefaults(suiteName: "app.binmate.checks")!
scratchDefaults.removePersistentDomain(forName: "app.binmate.checks")

for city in library.cities {
    scratchDefaults.set(city.id, forKey: "selectedCityID")
    check(
        lookup.currentCity(defaults: scratchDefaults)?.id == city.id,
        "BinLookup should honour the stored city \(city.id)"
    )

    for item in QuickItem.allCases {
        guard let answer = lookup.answer(for: item, defaults: scratchDefaults) else {
            check(false, "\(city.displayName): no answer for \(item.displayName)")
            continue
        }
        check(
            answer.verdict.stream.id != "unknown",
            "\(city.displayName): '\(item.displayName)' hit the placeholder stream"
        )
        check(
            answer.spoken.contains(city.displayName),
            "\(city.displayName): spoken answer should name the city"
        )
        check(
            answer.spoken.contains(item.displayName),
            "\(city.displayName): spoken answer should name the item"
        )
        // An item that is really several parts must not let Siri imply one bin is the
        // whole story — that is the exact mistake this app exists to correct.
        if item.isMultiPartInReality {
            check(
                answer.spoken.lowercased().contains("just the main part"),
                "\(city.displayName): '\(item.displayName)' is multi-part and must say so"
            )
        }
    }
}

// A stored city that no longer exists must fall back rather than go silent.
scratchDefaults.set("xx-nowhere", forKey: "selectedCityID")
check(lookup.currentCity(defaults: scratchDefaults) != nil, "an unknown stored city should fall back")
scratchDefaults.removePersistentDomain(forName: "app.binmate.checks")

// Deposits have to survive into the spoken answer, or Siri tells someone to bin money.
scratchDefaults.set("de-berlin", forKey: "selectedCityID")
if let bottle = lookup.answer(for: .plasticBottle, defaults: scratchDefaults) {
    check(bottle.verdict.stream.id == "pfand", "Berlin plastic bottle should be a deposit return")
    check(bottle.spoken.contains("25 cents"), "Berlin answer should mention the refund")
    // Said once, not twice: the city's instruction already names the amount, so the
    // generated "worth 0,25 € back" sentence must be suppressed.
    check(
        !bottle.spoken.contains("worth"),
        "Berlin answer repeats the refund — the instruction already states it"
    )
    check(bottle.spoken.contains("goes to"), "a deposit return is somewhere you go to, not a bin you put things in")
    print("  Berlin: \(bottle.spoken)")
}
// A plain bin keeps the "goes in" phrasing.
scratchDefaults.set("pl-krakow", forKey: "selectedCityID")
if let box = lookup.answer(for: .cardboardBox, defaults: scratchDefaults) {
    check(box.spoken.contains("goes in"), "a bin is somewhere you put things in")
    print("  Kraków: \(box.spoken)")
}
// Where the instruction says nothing about money, the refund must still be announced.
scratchDefaults.set("us-san-francisco", forKey: "selectedCityID")
if let can = lookup.answer(for: .drinksCan, defaults: scratchDefaults) {
    check(
        can.verdict.depositValue == nil || can.spoken.contains("cent") || can.spoken.contains("worth"),
        "San Francisco answer should still convey the CRV refund somehow"
    )
    print("  SF:     \(can.spoken)")
}
scratchDefaults.set("jp-tokyo-shibuya", forKey: "selectedCityID")
if let cup = lookup.answer(for: .compostableCup, defaults: scratchDefaults) {
    print("  Tokyo:  \(cup.spoken)")
}
scratchDefaults.removePersistentDomain(forName: "app.binmate.checks")

// MARK: - Siri display names cannot drift from the app's

// `QuickItemAppEnum.caseDisplayRepresentations` must be a compile-time literal — the App
// Intents metadata processor rejects anything computed — so it cannot be derived from
// QuickItem.displayName. That makes drift possible, so the literal is read back from
// source and compared.
let intentSource = ProcessInfo.processInfo.environment["BINMATE_INTENT_SOURCE"]
    ?? "BinMate/Services/WhichBinIntent.swift"

if let source = try? String(contentsOfFile: intentSource, encoding: .utf8) {
    for item in QuickItem.allCases {
        let expected = ".\(item.rawValue): \"\(item.displayName)\""
        check(
            source.contains(expected),
            "WhichBinIntent.swift is missing or has drifted from `\(expected)`"
        )
    }
    print("\nSiri display names match the app's for all \(QuickItem.allCases.count) items.")
} else {
    check(false, "could not read \(intentSource) to compare Siri display names")
}

// MARK: - The rule book

print("\nRule book coverage:")

for city in library.cities {
    let guide = CityGuide(ruleset: city)
    let engine = RulesEngine(ruleset: city)

    // Every rule must be reachable from some stream's page, or the browser is lying
    // about what the city does.
    let listed = guide.orderedStreams.reduce(0) { $0 + guide.entries(forStream: $1.id).count }
    check(
        listed == city.rules.count,
        "\(city.displayName): rule book lists \(listed) of \(city.rules.count) rules"
    )

    // Browsing and scanning read the same ruleset, so they must never disagree.
    for result in guide.search("bottle") {
        let viaGuide = result.verdict.stream.id
        let candidate = CityGuide.candidates.first { $0.label == result.label }
        if let candidate {
            let viaEngine = engine.verdict(for: candidate.component).stream.id
            check(
                viaGuide == viaEngine,
                "\(city.displayName): search says \(viaGuide) for '\(result.label)' but the engine says \(viaEngine)"
            )
        }
    }

    // The catch-all must be listed last — it is the answer you want when nothing matched.
    check(
        guide.orderedStreams.last?.id == city.defaultStreamID,
        "\(city.displayName): the default stream should be listed last"
    )

    let covered = Set(city.rules.map(\.stream)).count
    print("  \(city.flag) \(city.displayName): \(city.rules.count) rules over \(covered)/\(city.streams.count) streams")
}

// Search has to behave like a search: prefixes, synonyms, and nothing for nonsense.
let berlinGuide = CityGuide(ruleset: library.city(id: "de-berlin")!)

check(!berlinGuide.search("yog").isEmpty, "a prefix should match 'yogurt pot'")
check(
    berlinGuide.search("yog").first?.label == "yogurt pot",
    "the best match for 'yog' should be the yogurt pot"
)
check(!berlinGuide.search("tetra pak").isEmpty, "a synonym should match the drinks carton")
check(!berlinGuide.search("tin foil").isEmpty, "a synonym should match the foil wrapper")
check(berlinGuide.search("qqzzxx").isEmpty, "nonsense should return nothing")
check(berlinGuide.search("   ").isEmpty, "whitespace should return nothing")
check(berlinGuide.search("bottle", limit: 2).count <= 2, "the limit should be respected")

// An exact name must outrank a mere substring: typing "cap" should find the bottle cap,
// not something that merely contains those letters.
check(
    berlinGuide.search("bottle cap").first?.label == "bottle cap",
    "an exact name should rank first"
)

// The deposit has to survive into search results, or the list quietly tells someone to
// bin a refundable bottle.
if let bottle = berlinGuide.search("plastic bottle").first {
    check(bottle.verdict.depositValue != nil, "Berlin search should carry the bottle deposit")
}

// MARK: - Nearest city

print("\nNearest-city matching:")

// Every ruleset needs coordinates, or it can never be detected.
for city in library.cities {
    check(
        city.latitude != nil && city.longitude != nil,
        "\(city.displayName) has no coordinates and can never be matched by location"
    )
}

// A known distance, to catch a broken haversine rather than trusting it.
// Berlin to Kraków is roughly 520 km.
let berlinToKrakow = NearestCity.distanceKm(from: (52.5200, 13.4050), to: (50.0647, 19.9450))
check(
    (500...540).contains(berlinToKrakow),
    "Berlin→Kraków should be about 520 km, got \(Int(berlinToKrakow))"
)
check(
    NearestCity.distanceKm(from: (52.52, 13.405), to: (52.52, 13.405)) < 0.001,
    "distance from a point to itself should be zero"
)

struct Spot {
    var name: String
    var lat: Double
    var lon: Double
    var expectedCity: String
    var expectTrustworthy: Bool
}

let spots = [
    Spot(name: "Kraków, Main Square", lat: 50.0616, lon: 19.9373, expectedCity: "pl-krakow", expectTrustworthy: true),
    Spot(name: "Berlin, Alexanderplatz", lat: 52.5219, lon: 13.4132, expectedCity: "de-berlin", expectTrustworthy: true),
    Spot(name: "San Francisco, Mission", lat: 37.7599, lon: -122.4148, expectedCity: "us-san-francisco", expectTrustworthy: true),
    Spot(name: "Tokyo, Shibuya Crossing", lat: 35.6595, lon: 139.7005, expectedCity: "jp-tokyo-shibuya", expectTrustworthy: true),
    // Potsdam is outside Berlin but close enough that the rules usually still hold.
    Spot(name: "Potsdam", lat: 52.3906, lon: 13.0645, expectedCity: "de-berlin", expectTrustworthy: true),
    // Madrid's nearest ruleset is Berlin, and Spain sorts differently. The app must not
    // pretend this is an answer.
    Spot(name: "Madrid", lat: 40.4168, lon: -3.7038, expectedCity: "de-berlin", expectTrustworthy: false),
    // Kraków, not Berlin — Nairobi really is ~600 km closer to it. Which is the point:
    // "nearest" carries no meaning at this range, and the app must say so.
    Spot(name: "Nairobi", lat: -1.2921, lon: 36.8219, expectedCity: "pl-krakow", expectTrustworthy: false),
]

for spot in spots {
    guard let match = NearestCity.match(latitude: spot.lat, longitude: spot.lon, in: library.cities) else {
        check(false, "\(spot.name): no match at all")
        continue
    }
    check(
        match.city.id == spot.expectedCity,
        "\(spot.name): expected \(spot.expectedCity), got \(match.city.id)"
    )
    check(
        match.confidence.isTrustworthy == spot.expectTrustworthy,
        "\(spot.name): trustworthy should be \(spot.expectTrustworthy) at \(Int(match.distanceKm)) km"
    )
    print("  \(spot.name) → \(match.city.displayName), \(Int(match.distanceKm)) km — \(match.confidence.isTrustworthy ? "auto-applies" : "offered, not applied")")
}

// The far-away wording has to actually warn, not just hedge.
if let madrid = NearestCity.match(latitude: 40.4168, longitude: -3.7038, in: library.cities) {
    check(
        madrid.summary.lowercased().contains("probably do not apply"),
        "a far-away match must say its rules probably do not apply"
    )
    print("  Madrid summary: \(madrid.summary)")
}

// A ruleset without coordinates must be skipped rather than crash or win.
var coordinateless = library.cities[0]
coordinateless.latitude = nil
coordinateless.longitude = nil
check(
    NearestCity.match(latitude: 0, longitude: 0, in: [coordinateless]) == nil,
    "a ruleset with no coordinates should never match"
)

// MARK: - Bin colour legibility

// Bin colours come from municipalities, not from a palette anyone designed for screens.
// Berlin's yellow and its pale Weißglas grey both swallow a white symbol. Rather than
// check this by looking at screenshots, measure it: WCAG wants 3:1 for large graphics,
// and these are large glyphs inside a filled circle.
print("\nSymbol contrast on bin colours:")

let minimumContrast = 3.0
var worst = (name: "", ratio: Double.greatestFiniteMagnitude)

for city in library.cities {
    for stream in city.streams {
        check(
            stream.rgbComponents != nil,
            "\(city.displayName)/\(stream.name): colorHex '\(stream.colorHex)' is not a valid colour"
        )
        let ratio = stream.symbolContrastRatio
        check(
            ratio >= minimumContrast,
            String(
                format: "%@/%@ (#%@): symbol contrast is only %.2f:1, below %.1f:1",
                city.displayName, stream.name, stream.colorHex, ratio, minimumContrast
            )
        )
        if ratio < worst.ratio {
            worst = ("\(city.displayName)/\(stream.name)", ratio)
        }
    }
}
print(String(format: "  tightest: %@ at %.2f:1 (floor %.1f:1)", worst.name, worst.ratio, minimumContrast))

// The light-colour cases must actually flip to a dark symbol, or the rule is not working.
if let berlin = library.city(id: "de-berlin") {
    if let yellow = berlin.stream(id: "gelbe") {
        check(yellow.prefersDarkSymbol, "Berlin's yellow bin needs a dark symbol")
    }
    if let clearGlass = berlin.stream(id: "weissglas") {
        check(clearGlass.prefersDarkSymbol, "Berlin's pale Weißglas needs a dark symbol")
    }
    if let paper = berlin.stream(id: "blaue") {
        check(!paper.prefersDarkSymbol, "Berlin's deep blue bin should keep a white symbol")
    }
}

// A malformed colour must degrade rather than crash or render invisibly.
let broken = WasteStream(
    id: "x", name: "Broken", localName: nil, colorHex: "nonsense",
    symbol: "trash", kind: .residual, depositAmount: nil, depositCurrencyCode: nil
)
check(broken.rgbComponents == nil, "a malformed hex should not parse")
check(!broken.prefersDarkSymbol, "a malformed colour should fall back to a white symbol on grey")

print(failures == 0 ? "\nAll bundle checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
