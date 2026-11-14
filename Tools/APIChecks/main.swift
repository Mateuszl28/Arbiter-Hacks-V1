import Foundation

// Hits the live Open Food Facts API and checks that real responses survive the client's
// parsing and resolve to real verdicts.
//
// Kept separate from the other suites because it needs a network and depends on data
// other people can edit, so it must never gate a build. Run it when touching the client.

let barcodes = CommandLine.arguments.count > 1
    ? Array(CommandLine.arguments.dropFirst())
    : [
        "5449000000996",  // Coca-Cola 500 ml — widely contributed packaging data
        "3017620422003",  // Nutella 400 g — multi-material: glass, plastic, paper
        "4000417025005",  // Returns en:pp-5-polypropylene — a resin-coded identifier
        "8000500310427",  // Returns en:o-7-other-plastics
        "0000000000000",  // Should be a clean "not found", not a crash
    ]

let rulesBase = ProcessInfo.processInfo.environment["BINMATE_RULES"] ?? "Shared/Rules"
let cities = try ["pl-krakow.json", "de-berlin.json", "us-san-francisco.json"].map {
    try JSONDecoder().decode(
        CityRuleset.self,
        from: Data(contentsOf: URL(fileURLWithPath: rulesBase + "/" + $0))
    )
}

let client = OpenFoodFactsClient()
var failures = 0
var reachedService = false

func fail(_ message: String) {
    failures += 1
    print("  FAIL: \(message)")
}

for barcode in barcodes {
    print("\n=== \(barcode) ===")
    do {
        let product = try await client.product(barcode: barcode)
        reachedService = true

        print("  \(product.displayTitle)")
        print("  origin: \(product.origin.rawValue), \(product.components.count) component(s)")

        if product.components.isEmpty {
            fail("\(barcode): returned a product with no components — should have thrown .noPackagingData")
        }
        if product.origin != .openFoodFacts {
            fail("\(barcode): live result should be labelled .openFoodFacts, got \(product.origin.rawValue)")
        }

        for component in product.components {
            // Every material must land on a known taxonomy root, otherwise the ancestry
            // walk has nothing to fall back to and verdicts become city defaults.
            let ancestry = MaterialTaxonomy.ancestry(of: component.material)
            let roots = ancestry.map(\.value)
            print("    \(component.headline)  [\(roots.joined(separator: " -> "))]")

            // A material the taxonomy cannot place is a bug in BinMate, not a gap in a
            // city's rules — and it is the failure mode that is easy to miss, because
            // the app still gives a confident-looking answer. This check previously
            // printed such cases as a note and passed, which is how seven resin-code
            // identifiers returned by this very API went unnoticed while every plastic
            // in the database resolved to residual waste.
            if !MaterialTaxonomy.isKnown(MaterialTaxonomy.canonical(component.material)) {
                fail("\(barcode): the live API returned '\(component.material.value)', which the taxonomy does not know")
            }

            for city in cities {
                let verdict = RulesEngine(ruleset: city).verdict(for: component)
                if verdict.stream.id == "unknown" {
                    fail("\(barcode): \(component.headline) hit the placeholder stream in \(city.displayName)")
                }
                if verdict.quality == .cityDefault {
                    print("      note: no specific rule in \(city.displayName) -> \(verdict.stream.name)")
                }
            }
        }
    } catch let error as ProductLookupError {
        reachedService = true
        switch error {
        case .notFound(let code):
            print("  not found: \(code)  (expected for the deliberate bad barcode)")
            if barcode != "0000000000000" {
                fail("\(barcode): unexpectedly not found")
            }
        case .noPackagingData(let name):
            print("  no packaging data for '\(name)' — handled, routes to the manual picker")
        case .offline:
            print("  offline — skipping (this suite needs a network)")
        case .server(let status):
            print("  service returned HTTP \(status) — skipping")
        case .malformedResponse:
            fail("\(barcode): response did not parse — the client's leniency needs work")
        }
    } catch {
        fail("\(barcode): unexpected error \(error)")
    }
}

if !reachedService {
    print("\nCould not reach Open Food Facts — nothing was verified.")
    exit(0)
}

print(failures == 0 ? "\nAll live API checks passed." : "\n\(failures) check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
