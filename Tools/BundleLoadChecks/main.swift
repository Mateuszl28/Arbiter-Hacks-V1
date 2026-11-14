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

check(library.cities.count == 5, "expected 5 cities, got \(library.cities.count)")
check(library.problems.isEmpty, "ruleset loading should report no problems")
for expected in ["pl-krakow", "de-berlin", "us-san-francisco", "jp-tokyo-shibuya", "us-new-york-city"] {
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

// MARK: - Take-back list

print("\nTake-back list:")

var recordCounter = 0
func record(_ product: ScannedProduct, cityID: String, name: String) -> (
    key: TakeBackList.RecordKey, productName: String, scannedAt: Date, cityID: String, product: ScannedProduct
) {
    recordCounter += 1
    return (
        key: TakeBackList.RecordKey(recordCounter),
        productName: name,
        scannedAt: Date(timeIntervalSince1970: 0),
        cityID: cityID,
        product: product
    )
}

let sixCans = ScannedProduct(
    barcode: nil, name: "Six cans", brand: nil, imageURL: nil,
    components: [PackagingComponent(shape: "en:can", material: "en:aluminium", numberOfUnits: 6)],
    origin: .manual
)
let cardboardOnly = ScannedProduct(
    barcode: nil, name: "Plain box", brand: nil, imageURL: nil,
    components: [PackagingComponent(shape: "en:box", material: "en:cardboard")],
    origin: .manual
)
let corkOnly = ScannedProduct(
    barcode: nil, name: "Cork", brand: nil, imageURL: nil,
    components: [PackagingComponent(material: "en:cork")],
    origin: .manual
)

// Six cans scanned in Berlin: 6 x 0.25 = 1.50 EUR, as one deposit destination.
let berlinCans = TakeBackList.build(
    records: [record(sixCans, cityID: "de-berlin", name: "Six cans")],
    library: library
)
check(berlinCans.destinations.count == 1, "six cans should produce one destination")
check(berlinCans.destinations.first?.unitCount == 6, "the six cans should be counted individually")
check(
    berlinCans.valueByCurrency.first?.amount == Decimal(string: "1.50"),
    "six Berlin cans should total 1.50, got \(berlinCans.valueByCurrency)"
)

// A kerbside-only item must never appear. A bin is not a to-do list.
let boxOnly = TakeBackList.build(
    records: [record(cardboardOnly, cityID: "de-berlin", name: "Plain box")],
    library: library
)
check(boxOnly.isEmpty, "a plain cardboard box needs no trip and must not be listed")

// Drop-off items have no money but still need carrying — Berlin collects cork separately.
let berlinCork = TakeBackList.build(
    records: [record(corkOnly, cityID: "de-berlin", name: "Cork")],
    library: library
)
check(!berlinCork.isEmpty, "Berlin cork goes to a drop-off point and should be listed")
check(
    berlinCork.destinations.first?.stream.kind == .dropOff,
    "cork should be listed as a drop-off, not a deposit"
)
check(
    berlinCork.valueByCurrency.isEmpty,
    "a drop-off with no deposit must not claim a refund"
)

// Scanned in one city, reckoned in that city. A bottle scanned in Berlin is worth 25
// cents at a German machine regardless of where its owner is standing today.
let mixedTrip = TakeBackList.build(
    records: [
        record(sixCans, cityID: "de-berlin", name: "Berlin cans"),
        record(sixCans, cityID: "us-san-francisco", name: "SF cans"),
    ],
    library: library
)
check(mixedTrip.destinations.count == 2, "two cities should not be merged into one trip")
let currencies = Set(mixedTrip.valueByCurrency.map(\.currency))
check(currencies == ["EUR", "USD"], "each city's deposit should stay in its own currency, got \(currencies)")
for entry in mixedTrip.valueByCurrency {
    print("  \(entry.amount.formattedCurrency(code: entry.currency)) waiting in \(entry.currency)")
}

// Money first: a destination worth something outranks one that is merely a chore.
let ordered = TakeBackList.build(
    records: [
        record(corkOnly, cityID: "de-berlin", name: "Cork"),
        record(sixCans, cityID: "de-berlin", name: "Cans"),
    ],
    library: library
)
check(
    ordered.destinations.first?.totalValue ?? 0 > 0,
    "the destination worth money should be listed first"
)

// Cities with no deposit scheme must simply produce nothing rather than a zero total.
let krakowCans = TakeBackList.build(
    records: [record(sixCans, cityID: "pl-krakow", name: "Cans")],
    library: library
)
check(
    krakowCans.valueByCurrency.isEmpty,
    "Kraków has no deposit scheme, so there is nothing to reclaim"
)

// MARK: - What the widget shows

// The widget lists bins at a glance. A deposit machine or a drop-off centre is a
// destination, not a bin, and listing one beside "Gelbe Tonne" would imply there is one
// standing in the kitchen.
print("\nWidget bin lists:")

for city in library.cities {
    let kerbside = city.kerbsideStreams
    check(
        kerbside.allSatisfy { $0.kind != .deposit && $0.kind != .dropOff },
        "\(city.displayName): the widget list must contain no deposit or drop-off stream"
    )
    check(
        kerbside.count >= 2,
        "\(city.displayName): a glance should show at least two bins, got \(kerbside.count)"
    )
    // The catch-all has to be there: "everything else" is the most useful line on a bin
    // list, and omitting it would make the widget look more decisive than the rules are.
    check(
        kerbside.contains { $0.id == city.defaultStreamID },
        "\(city.displayName): the default bin should appear in the widget list"
    )
    let named = kerbside.compactMap(\.localName).filter { !$0.isEmpty }
    print("  \(city.flag) \(city.displayName): \(kerbside.count) bins (\(named.count) with a local name)")
}

// Every city must survive a fresh install, where no city has been chosen yet.
let emptyDefaults = UserDefaults(suiteName: "app.binmate.widgetcheck")!
emptyDefaults.removePersistentDomain(forName: "app.binmate.widgetcheck")
check(library.fallbackCity != nil, "the widget needs a fallback city when none is stored")

// MARK: - Widget configuration

// The widget carries its own city because the App Group that would carry the app's
// choice needs a provisioning profile an unsigned build does not have. This is the list
// the configuration sheet offers, and it must never drift from what the app can sort
// against.
print("\nWidget city picker:")

// In the extension this reads the appex bundle; here it must be pointed at the built
// app bundle, because a host test binary carries no rules of its own.
CityEntityQuery.library = library

let offered = try await CityEntityQuery().suggestedEntities()
check(
    offered.count == library.cities.count,
    "the picker should offer every bundled city, got \(offered.count) of \(library.cities.count)"
)
check(
    Set(offered.map(\.id)) == Set(library.cities.map(\.id)),
    "the picker's ids must match the loaded rulesets exactly"
)
for entity in offered {
    print("  \(entity.name) — \(entity.regionCode)")
}

// Round-tripping an id is what WidgetKit does when it restores a configured widget.
let restored = try await CityEntityQuery().entities(for: ["jp-tokyo-shibuya"])
check(restored.first?.name == "Tokyo (Shibuya)", "a stored id should restore to its city")

// An id from a ruleset that no longer ships must drop out rather than crash or
// resurrect as a blank entry.
let stale = try await CityEntityQuery().entities(for: ["xx-nowhere"])
check(stale.isEmpty, "an unknown city id should resolve to nothing")

// A freshly added widget must land on a real city rather than an empty face.
let fallback = await CityEntityQuery().defaultResult()
check(fallback != nil, "a new widget needs a default city")
check(
    library.city(id: fallback?.id ?? "") != nil,
    "the default city must be one that actually loaded"
)

// MARK: - Ways in from outside

// The widget's description promises a tap opens the scanner, and the Shortcuts action
// promises the same. Both were descriptions before they were behaviour; these assert the
// routes that now carry them.
print("\nDeep links:")

check(DeepLink.isScanRequest(DeepLink.scan), "the widget's own URL must be recognised")
check(DeepLink.scan.scheme == "binmate", "the scheme must match the one registered in Info.plist")
print("  widget opens: \(DeepLink.scan)")

// Case should not decide whether someone reaches the scanner.
check(
    DeepLink.isScanRequest(URL(string: "BinMate://SCAN")!),
    "the scheme and host should match case-insensitively"
)
// Anything else must be ignored rather than treated as a scan request.
for rejected in ["binmate://settings", "https://binmate.app/scan", "otherapp://scan", "binmate://"] {
    check(
        !DeepLink.isScanRequest(URL(string: rejected)!),
        "'\(rejected)' should not be read as a scan request"
    )
}

// The Shortcuts action leaves a request behind instead of a URL, because it runs inside
// the app's own process. It has to be consumed exactly once.
let actionDefaults = UserDefaults(suiteName: "app.binmate.actioncheck")!
actionDefaults.removePersistentDomain(forName: "app.binmate.actioncheck")

check(
    !PendingAction.consumeScannerRequest(in: actionDefaults),
    "a fresh install should have no pending scanner request"
)
PendingAction.requestScanner(in: actionDefaults)
check(
    PendingAction.consumeScannerRequest(in: actionDefaults),
    "a request left by the Shortcuts action should be picked up"
)
// Consumed means gone: a relaunch days later must not reopen the scanner out of nowhere.
check(
    !PendingAction.consumeScannerRequest(in: actionDefaults),
    "a consumed request must not fire again on the next launch"
)
actionDefaults.removePersistentDomain(forName: "app.binmate.actioncheck")

// MARK: - Rule conflicts

// Cities being data is only an advantage if the data can be checked. A rule written in
// good faith can still be dead — shadowed by a broader one above it — and nothing in the
// app would say so: the verdict would just be quietly wrong, with a confident
// explanation attached.
print("\nRule conflicts:")

var totalWarnings = 0
for city in library.cities {
    let findings = RuleConflicts.findings(in: city)
    let errors = findings.filter { $0.severity == .error }
    let warnings = findings.filter { $0.severity == .warning }
    totalWarnings += warnings.count

    for finding in findings {
        print("  \(finding.severity == .error ? "ERROR  " : "warning")  \(city.displayName) rule \(finding.ruleIndex + 1): \(finding.message)")
    }
    check(
        errors.isEmpty,
        "\(city.displayName) has \(errors.count) unreachable or contradictory rule(s)"
    )
}
if totalWarnings == 0 {
    print("  none across \(library.cities.count) cities")
}

// The detector has to be able to fire, or it is decoration. A deliberately broken
// ruleset must be caught.
let shadowed = CityRuleset(
    id: "test", displayName: "Test", region: "Nowhere", flag: "", regionCode: "XX",
    latitude: nil, longitude: nil, compiledOn: "2026-01-01", sourceName: "test",
    sourceURL: nil,
    streams: [
        WasteStream(id: "a", name: "A", localName: nil, colorHex: "000000", symbol: "trash", kind: .recycling, depositAmount: nil, depositCurrencyCode: nil),
        WasteStream(id: "b", name: "B", localName: nil, colorHex: "FFFFFF", symbol: "trash", kind: .residual, depositAmount: nil, depositCurrencyCode: nil),
    ],
    rules: [
        // Broad rule first…
        BinRule(materials: ["en:plastic"], shapes: nil, stream: "a", instruction: nil, caution: nil),
        // …so this one can never fire, and would have sent the bottle somewhere else.
        BinRule(materials: ["en:plastic"], shapes: ["en:bottle"], stream: "b", instruction: nil, caution: nil),
    ],
    defaultStreamID: "b"
)
let caught = RuleConflicts.findings(in: shadowed)
check(
    caught.contains { $0.severity == .error && $0.ruleIndex == 1 },
    "a rule shadowed by a broader one above it must be reported as an error"
)
// And it must not cry wolf: the same pair in the correct order is fine.
let correctOrder = CityRuleset(
    id: "test2", displayName: "Test", region: "Nowhere", flag: "", regionCode: "XX",
    latitude: nil, longitude: nil, compiledOn: "2026-01-01", sourceName: "test",
    sourceURL: nil,
    streams: shadowed.streams,
    rules: [shadowed.rules[1], shadowed.rules[0]],
    defaultStreamID: "b"
)
check(
    RuleConflicts.findings(in: correctOrder).allSatisfy { $0.severity != .error },
    "the specific-before-general order is correct and must not be reported"
)

// MARK: - Packaging change detection

// Producers change packaging and rarely announce it. Matching is by part rather than by
// position, because contributors list components in no order and matching on index would
// report nonsense every time somebody reordered a record.
print("\nPackaging changes:")

let oldBottle = [
    PackagingComponent(shape: "en:bottle", material: "en:clear-glass"),
    PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene"),
    PackagingComponent(shape: "en:label", material: "en:paper"),
]
let newBottle = [
    // Same three parts, but the bottle is now plastic.
    PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene"),
    PackagingComponent(shape: "en:label", material: "en:paper"),
    PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate"),
]

let diff = PackagingDiff.between(previous: oldBottle, current: newBottle)
check(diff.changes.count == 1, "only the bottle changed, got \(diff.changes.count) change(s)")
check(
    diff.changes.contains { if case .materialChanged = $0 { return true }; return false },
    "a swapped material should read as a change, not an add plus a remove"
)
for change in diff.changes { print("  \(change.summary)") }

// Reordering alone must report nothing. This is the whole reason matching is by part.
let reordered = Array(oldBottle.reversed())
check(
    PackagingDiff.between(previous: oldBottle, current: reordered).isEmpty,
    "reordering the same components must not be reported as a change"
)
check(
    PackagingDiff.between(previous: oldBottle, current: oldBottle).isEmpty,
    "an identical rescan is not news"
)

// Added and removed parts.
let withSeal = oldBottle + [PackagingComponent(shape: "en:seal", material: "en:aluminium")]
check(
    PackagingDiff.between(previous: oldBottle, current: withSeal).changes.count == 1,
    "a new part should be one change"
)
check(
    PackagingDiff.between(previous: withSeal, current: oldBottle).changes.contains {
        if case .removed = $0 { return true }; return false
    },
    "a vanished part should be reported as removed"
)

// A count change is a change, but never moves a bin.
let sixPack = [PackagingComponent(shape: "en:can", material: "en:aluminium", numberOfUnits: 6)]
let fourPack = [PackagingComponent(shape: "en:can", material: "en:aluminium", numberOfUnits: 4)]
let countDiff = PackagingDiff.between(previous: sixPack, current: fourPack)
check(countDiff.changes.count == 1, "a quantity change is a change")
if let berlin = library.city(id: "de-berlin") {
    check(
        countDiff.binAffecting(under: RulesEngine(ruleset: berlin)).isEmpty,
        "a quantity change must not be reported as moving a bin"
    )
    // Glass to PET in Berlin really does move the bin — glass container to deposit return.
    let moving = diff.binAffecting(under: RulesEngine(ruleset: berlin))
    check(!moving.isEmpty, "glass → PET in Berlin should be flagged as moving the bin")
    print("  bin-affecting in Berlin: \(moving.count) of \(diff.changes.count)")
}

// MARK: - Coverage and knowledge gaps

// The bottleneck here is research per city, not code. Counting gaps without weighting
// them would point the work at whatever is alphabetically first.
print("\nRule coverage:")

let coverage = CoverageAnalysis.analyse(cities: library.cities)
for entry in coverage.byCity.sorted(by: { $0.specific > $1.specific }) {
    print("  \(entry.cityName): \(entry.specific) specific, \(entry.inherited) general, \(entry.missing) uncovered")
}

let common = MaterialTaxonomy.pickerMaterials.count
for entry in coverage.byCity {
    check(
        entry.specific + entry.inherited + entry.missing == common,
        "\(entry.cityName): every common material must be accounted for exactly once"
    )
}

// Gaps must be ordered worst-first, then by how common the material is — not
// alphabetically, or the queue points at the wrong work.
if coverage.gaps.count > 1 {
    let levels = coverage.gaps.map(\.level.rawValue)
    check(levels == levels.sorted(), "gaps should be ordered worst level first")
}
if let worst = coverage.gaps.first {
    print("  most urgent gap: \(worst.summary) (\(worst.priority) priority)")
}
check(
    coverage.gaps.allSatisfy { $0.level != .specific },
    "a material with its own rule is not a gap"
)

// MARK: - Decision audit trail

// Everything else in this project recomputes, which quietly rewrites history: a scan from
// last spring is shown against today's rules, so a user who remembers being told
// something different has no way to show it. Recording the decision fixes that, and makes
// one more question answerable — would today's rules say the same?
print("\nDecision audit trail:")

guard let berlinCity = library.city(id: "de-berlin") else { exit(1) }
let auditEngine = RulesEngine(ruleset: berlinCity)
let auditedProduct = ScannedProduct(
    barcode: "1", name: "Audited bottle", brand: nil, imageURL: nil,
    components: [
        PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate"),
        PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene"),
    ],
    origin: .manual
)
let recordedNow = auditEngine.verdicts(for: auditedProduct).map {
    RecordedDecision(verdict: $0, cityID: berlinCity.id)
}

// Against the same rules, nothing has changed. The obvious case, and the one that must
// not produce noise — a badge on every row would be worthless.
check(
    DecisionReview.review(recorded: recordedNow, product: auditedProduct, library: library) == .unchanged,
    "a decision recorded under today's rules must review as unchanged"
)

// A scan from before decisions were recorded must stay silent rather than guess.
check(
    DecisionReview.review(recorded: [], product: auditedProduct, library: library) == .notRecorded,
    "an unrecorded scan should say so rather than invent a comparison"
)

// A ruleset that no longer ships must be named, not silently ignored.
var orphaned = recordedNow
orphaned[0].cityID = "xx-nowhere"
if case .rulesetGone = DecisionReview.review(recorded: orphaned, product: auditedProduct, library: library) {
    print("  a removed ruleset is reported rather than ignored")
} else {
    check(false, "a decision recorded under a removed ruleset should be reported")
}

// The real case: the rules changed since. Pretend the bottle was once sent to the yellow
// bin rather than the deposit machine — exactly the correction that would matter.
var corrected = recordedNow
corrected[0].streamID = "gelbe"
corrected[0].streamName = "Packaging"
let outcome = DecisionReview.review(recorded: corrected, product: auditedProduct, library: library)
check(outcome.movesABin, "a changed destination must be reported as moving a bin")
if case .changed(let differences) = outcome {
    check(differences.count == 1, "only the bottle changed, got \(differences.count)")
    for difference in differences { print("  \(difference.summary)") }
}

// A change in reasoning that lands in the same bin is worth showing but must not be
// dressed up as a moved bin.
var reasoningOnly = recordedNow
reasoningOnly[1].quality = "exactMaterial"
let soft = DecisionReview.review(recorded: reasoningOnly, product: auditedProduct, library: library)
check(!soft.movesABin, "a reasoning-only change must not claim the bin moved")
if case .changed(let differences) = soft {
    check(differences.allSatisfy(\.sameBin), "and should be marked as same-bin")
    for difference in differences { print("  \(difference.summary)") }
}

// MARK: - Packaging anomalies and data quality

// Open Food Facts fails in specific ways rather than randomly: one catch-all component,
// the same part twice, a material and a shape that do not go together. None of these stop
// the engine — it will resolve a glass film perfectly happily — which is why they need
// catching. A confident answer about an implausible object is worse than no answer.
print("\nPackaging anomalies:")

func product(_ components: [PackagingComponent], name: String = "Test") -> ScannedProduct {
    ScannedProduct(barcode: nil, name: name, brand: nil, imageURL: nil, components: components, origin: .manual)
}

let thin = product([PackagingComponent(shape: "en:bottle", material: "en:plastic")])
check(
    PackagingAnomalyDetector.anomalies(in: thin).contains(.singleComponent),
    "a one-component record should be flagged as thin"
)

let duplicated = product([
    PackagingComponent(shape: "en:label", material: "en:paper"),
    PackagingComponent(shape: "en:label", material: "en:paper"),
    PackagingComponent(shape: "en:bottle", material: "en:clear-glass"),
])
check(
    PackagingAnomalyDetector.anomalies(in: duplicated).contains { if case .repeatedComponent = $0 { return true }; return false },
    "the same part listed twice should be flagged"
)

// A paper bottle is a contributor picking the wrong dropdown entry, not a product.
let implausible = product([
    PackagingComponent(shape: "en:bottle", material: "en:paper"),
    PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene"),
])
check(
    PackagingAnomalyDetector.anomalies(in: implausible).contains { if case .implausiblePairing = $0 { return true }; return false },
    "a paper bottle should be flagged as implausible"
)
for anomaly in PackagingAnomalyDetector.anomalies(in: implausible) { print("  \(anomaly.summary)") }

// And it must not cry wolf. A perfectly ordinary three-part bottle is clean.
let ordinary = product([
    PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate"),
    PackagingComponent(shape: "en:cap", material: "en:pp-polypropylene"),
    PackagingComponent(shape: "en:label", material: "en:paper"),
])
check(
    PackagingAnomalyDetector.anomalies(in: ordinary).isEmpty,
    "an ordinary bottle must produce no anomalies, or the detector becomes noise"
)
check(
    PackagingAnomalyDetector.anomalies(in: product([])).contains(.noComponents),
    "an empty record should be reported"
)

print("\nData quality report:")
let quality = DataQuality.assess(library: library, samples: samples)
print("  checked: \(quality.checked.cities) cities, \(quality.checked.rules) rules, \(quality.checked.materials) materials, \(quality.checked.products) products")
for issue in quality.issues.prefix(8) {
    print("  [\(issue.severity == .error ? "error" : (issue.severity == .warning ? "warn" : "info"))] \(issue.area): \(issue.detail)")
}
if quality.issues.count > 8 { print("  …and \(quality.issues.count - 8) more") }

check(quality.errors.isEmpty, "the bundled data should contain no errors, found \(quality.errors.count)")
// Every issue must carry something to do about it. A list of complaints with no remedies
// is a list nobody opens twice.
for issue in quality.issues {
    check(!issue.action.isEmpty, "every issue needs an action: \(issue.detail)")
    check(!issue.detail.isEmpty, "every issue needs a detail")
}
check(
    quality.checked.cities == library.cities.count,
    "the report must say how much it checked, not only what was wrong"
)
// Severity ordering, so the worst thing is not buried below a note.
let severities = quality.issues.map(\.severity.rawValue)
check(severities == severities.sorted(by: >), "issues should be ordered worst first")

// MARK: - Mass

// The field is free text and contributors write what they like into it. The one thing
// that must never happen is reading a volume as a mass: "25 cl" describes what was in the
// bottle, not what the bottle weighs, and treating them alike would turn a drinks aisle
// into hundreds of imaginary kilograms.
print("\nMass parsing:")

check(PackagingMass.gramsPerUnit(from: "24 g") == 24, "plain grams")
check(PackagingMass.gramsPerUnit(from: "220g") == 220, "no space")
check(PackagingMass.gramsPerUnit(from: "13 g each") == 13, "trailing words")
check(PackagingMass.gramsPerUnit(from: "1.5 kg") == 1500, "kilograms convert")
check(PackagingMass.gramsPerUnit(from: "1,5 kg") == 1500, "a comma decimal is still a number")
check(PackagingMass.gramsPerUnit(from: "500 mg") == 0.5, "milligrams convert")

// The refusals. Each of these would otherwise contribute a plausible-looking number.
for volume in ["25 cl", "330 ml", "1 l", "1.5 litre", "12 fl oz"] {
    check(
        PackagingMass.gramsPerUnit(from: volume) == nil,
        "'\(volume)' is a volume and must not be read as a mass"
    )
}
check(PackagingMass.gramsPerUnit(from: nil) == nil, "a missing field is missing, not zero")
check(PackagingMass.gramsPerUnit(from: "") == nil, "empty text yields nothing")
check(PackagingMass.gramsPerUnit(from: "one bottle") == nil, "words without a number yield nothing")

// Multipacks multiply.
let weighedCans = PackagingComponent(shape: "en:can", material: "en:aluminium", numberOfUnits: 6, quantityPerUnit: "13 g each")
check(PackagingMass.grams(for: weighedCans) == 78, "six 13 g cans should be 78 g, got \(PackagingMass.grams(for: weighedCans) ?? -1)")

print("\nMass ledger over the bundled samples:")
let ledger = MassLedger.build(
    scans: samples.products.map { (product: $0, cityID: "de-berlin") },
    library: library
)
print("  recognised: \(Int(ledger.recognisedGrams)) g across \(ledger.partsWithMass) of \(ledger.totalParts) parts (\(Int(ledger.coverage * 100))% coverage)")
print("  directed by a real rule: \(Int(ledger.directedGrams)) g")
for entry in ledger.byMaterial.prefix(4) {
    print("    \(MaterialTaxonomy.displayName(for: entry.material)): \(Int(entry.grams)) g over \(entry.parts) part(s)")
}

check(ledger.recognisedGrams > 0, "the bundled samples record some masses")
check(ledger.partsWithoutMass > 0, "and some without — the coverage figure has to mean something")
check(
    ledger.directedGrams <= ledger.recognisedGrams,
    "mass directed by a rule cannot exceed mass recognised"
)
check(
    abs(ledger.byMaterial.reduce(0) { $0 + $1.grams } - ledger.recognisedGrams) < 0.001,
    "the per-material breakdown must add up to the total"
)
check(
    ledger.coverage > 0 && ledger.coverage < 1,
    "coverage should be a real fraction here, got \(ledger.coverage)"
)

// MARK: - Follow-up questions

// The manual picker is what you offer when you have no idea what is missing. Usually the
// app does know, so it should ask one question rather than present an empty table — and
// just as importantly, it should stay quiet when there is nothing worth asking.
print("\nFollow-up questions:")

// A lone bottle: ask about the cap and the label, not about everything.
let loneBottle = product([PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate")])
let bottleQuestions = FollowUp.questions(for: loneBottle)
check(!bottleQuestions.isEmpty, "a lone bottle should prompt a question")
check(
    bottleQuestions.count <= FollowUp.limit,
    "no more than \(FollowUp.limit) questions, or it is a questionnaire"
)
for question in bottleQuestions { print("  \(question.prompt)") }

// A well-described product must be left alone. This is the check that keeps the feature
// from becoming nagging.
check(
    FollowUp.questions(for: ordinary).isEmpty,
    "a three-part bottle with everything described should prompt nothing"
)

// An unrecognised material blocks a real answer, so it outranks anything else.
let mysterious = product([
    PackagingComponent(shape: "en:cap", material: "en:unobtainium"),
    PackagingComponent(shape: "en:bottle", material: "en:pet-polyethylene-terephthalate"),
])
let mysteryQuestions = FollowUp.questions(for: mysterious)
check(mysteryQuestions.first?.id.hasPrefix("material-") == true, "an unknown material should be asked about first")
check(
    mysteryQuestions.first?.options.contains { $0.label.contains("PP") } == true,
    "a cap should be offered plausible cap materials"
)
check(
    mysteryQuestions.first?.options.last?.label == "Not sure",
    "every question needs an escape hatch"
)
print("  \(mysteryQuestions.first?.prompt ?? "")")

// Answering must actually change the product, and the engine must then agree.
guard let answered = mysteryQuestions.first?.options.first.map({
    FollowUp.apply($0.effect, to: mysterious)
}) else { exit(1) }
check(
    answered.components.allSatisfy { MaterialTaxonomy.isKnown($0.material) },
    "answering the material question should leave no unknown materials"
)
if let berlinNow = library.city(id: "de-berlin") {
    let engineNow = RulesEngine(ruleset: berlinNow)
    let before = engineNow.verdict(for: mysterious.components[0])
    let after = engineNow.verdict(for: answered.components[0])
    check(before.quality == .cityDefault, "the unknown cap fell to the default bin")
    check(after.quality != .cityDefault, "and answering should lift it off the default bin")
    print("  cap: \(before.stream.name) → \(after.stream.name) once answered")
}

// Declining must not mutate anything.
check(
    FollowUp.apply(.decline, to: mysterious).components == mysterious.components,
    "declining a question must leave the product untouched"
)

// A shapeless component cannot benefit from deposit or drop-off rules, which are written
// for shapes — so it is worth one question.
let shapeless = product([PackagingComponent(material: "en:aluminium")])
check(
    FollowUp.questions(for: shapeless).contains { $0.id.hasPrefix("shape-") },
    "a component with no shape should be asked about"
)

print(failures == 0 ? "\nAll bundle checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
