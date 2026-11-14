import Foundation

/// Reads a packaging mass out of the free text Open Food Facts stores.
///
/// The field is `quantity_per_unit` and contributors write what they like into it:
/// `24 g`, `13 g each`, `1.5 kg`, `220g`. It is parsed rather than guessed, and — the
/// part that matters — **volumes are refused**. `25 cl` describes what was *in* the
/// bottle, not what the bottle weighs, and treating the two alike would turn a drinks
/// aisle into hundreds of imaginary kilograms. A missing mass is reported as missing.
enum PackagingMass {
    /// Mass units only. Volume and count units are deliberately absent.
    private static let unitsToGrams: [(unit: String, grams: Double)] = [
        // Longest first, so "mg" is not read as "g".
        ("kg", 1000),
        ("mg", 0.001),
        ("lb", 453.592),
        ("oz", 28.3495),
        ("g", 1),
    ]

    /// Grams for one of this component, or nil when the record does not say.
    static func gramsPerUnit(from quantity: String?) -> Double? {
        guard let quantity else { return nil }
        let text = quantity.lowercased().replacingOccurrences(of: ",", with: ".")

        // Reject volumes outright rather than letting a number through with the wrong
        // meaning. This is the whole reason the parser exists.
        for volume in ["ml", "cl", "dl", " l", "litre", "liter", "fl oz"] where text.contains(volume) {
            return nil
        }

        guard let match = text.range(
            of: #"([0-9]+(\.[0-9]+)?)\s*(kg|mg|lb|oz|g)\b"#,
            options: .regularExpression
        ) else { return nil }

        let fragment = String(text[match])
        guard let value = Double(
            fragment.prefix(while: { $0.isNumber || $0 == "." })
        ) else { return nil }

        for entry in unitsToGrams where fragment.hasSuffix(entry.unit) {
            return value * entry.grams
        }
        return nil
    }

    /// Grams for the whole component, accounting for multipacks.
    static func grams(for component: PackagingComponent) -> Double? {
        gramsPerUnit(from: component.quantityPerUnit).map { $0 * Double(component.numberOfUnits) }
    }
}

/// What mass has passed through the app, and how much of it is actually known.
///
/// Three different things get called "recovered" and only one of them is honest here:
///
/// - **Recognised** — a mass is recorded for the part. Measurable from the data.
/// - **Directed** — that part also resolved to a specific or inherited rule rather than
///   falling into the catch-all. Still measurable.
/// - **Recovered** — what the sorting facility actually pulled out. BinMate has no way to
///   know this and does not claim it.
///
/// The ledger reports the first two and says plainly that the third is not its to report.
struct MassLedger: Sendable {
    struct Entry: Sendable, Identifiable {
        var id: String { material.value }
        var material: TaxonomyID
        var grams: Double
        var parts: Int
    }

    var byMaterial: [Entry]
    var recognisedGrams: Double
    /// Of the recognised mass, how much went to a stream chosen by a real rule.
    var directedGrams: Double
    /// Parts with a recorded mass, and parts without.
    var partsWithMass: Int
    var partsWithoutMass: Int

    var totalParts: Int { partsWithMass + partsWithoutMass }

    /// The figure that keeps the total honest. A total over 30% of parts is a different
    /// claim from a total over 95%.
    var coverage: Double {
        totalParts == 0 ? 0 : Double(partsWithMass) / Double(totalParts)
    }

    static func build(
        scans: [(product: ScannedProduct, cityID: String)],
        library: RulesLibrary
    ) -> MassLedger {
        var grams: [TaxonomyID: (grams: Double, parts: Int)] = [:]
        var recognised = 0.0
        var directed = 0.0
        var withMass = 0
        var withoutMass = 0

        for scan in scans {
            let engine = library.city(id: scan.cityID).map(RulesEngine.init(ruleset:))

            for component in scan.product.components {
                guard let mass = PackagingMass.grams(for: component) else {
                    withoutMass += 1
                    continue
                }
                withMass += 1
                recognised += mass

                let material = MaterialTaxonomy.canonical(component.material)
                let existing = grams[material] ?? (0, 0)
                grams[material] = (existing.grams + mass, existing.parts + 1)

                // Directed only counts when a rule actually chose the destination. Mass
                // that fell into a catch-all bin was not sorted by anything.
                if let verdict = engine?.verdict(for: component), verdict.quality != .cityDefault {
                    directed += mass
                }
            }
        }

        let entries = grams
            .map { Entry(material: $0.key, grams: $0.value.grams, parts: $0.value.parts) }
            .sorted { $0.grams > $1.grams }

        return MassLedger(
            byMaterial: entries,
            recognisedGrams: recognised,
            directedGrams: directed,
            partsWithMass: withMass,
            partsWithoutMass: withoutMass
        )
    }
}
