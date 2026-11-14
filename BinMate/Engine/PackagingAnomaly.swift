import Foundation

/// Packaging data that looks wrong before anyone tries to sort it.
///
/// Open Food Facts is contributed by volunteers, and the failure modes are specific
/// rather than random: a record with one catch-all component, the same part entered
/// twice, a material and a shape that do not go together. None of these stop the engine
/// — it will resolve a glass film perfectly happily — which is exactly why they need
/// catching. A confident answer about an implausible object is worse than no answer.
///
/// Checked at the product level rather than the component level, because the most
/// informative anomalies are about the record as a whole.
enum PackagingAnomaly: Hashable, Sendable {
    /// One component for a product that almost certainly has more.
    case singleComponent
    /// The same part and material listed more than once. Sometimes genuine — two
    /// identical pots — but usually a duplicated row.
    case repeatedComponent(shape: TaxonomyID?, material: TaxonomyID, times: Int)
    /// A material and a part that rarely occur together.
    case implausiblePairing(shape: TaxonomyID, material: TaxonomyID)
    /// A material the taxonomy has never heard of.
    case unknownMaterial(TaxonomyID)
    /// No components at all.
    case noComponents

    var summary: String {
        switch self {
        case .singleComponent:
            "Only one part is recorded. Most packaging has more."
        case .repeatedComponent(let shape, let material, let times):
            "\(ShapeTaxonomy.displayName(for: shape)) in \(MaterialTaxonomy.displayName(for: material)) is listed \(times) times."
        case .implausiblePairing(let shape, let material):
            "A \(ShapeTaxonomy.displayName(for: shape).lowercased()) made of \(MaterialTaxonomy.displayName(for: material).lowercased()) is unusual."
        case .unknownMaterial(let material):
            "\(material.humanized) is not a material BinMate knows."
        case .noComponents:
            "No packaging is recorded for this product."
        }
    }

    /// Whether this is likely a data problem rather than an unusual but real product.
    var isLikelyError: Bool {
        switch self {
        case .noComponents, .unknownMaterial: true
        case .singleComponent, .repeatedComponent, .implausiblePairing: false
        }
    }
}

enum PackagingAnomalyDetector {
    /// Pairings that effectively do not occur in household packaging.
    ///
    /// Kept deliberately short. A long list of "unusual" combinations would flag honest
    /// records constantly and be ignored within a week; these are the ones that indicate
    /// a contributor picked the wrong entry from a dropdown.
    private static let implausible: [(shape: TaxonomyID, materials: Set<TaxonomyID>)] = [
        ("en:bottle", ["en:paper", "en:cardboard", "en:corrugated-cardboard"]),
        ("en:film", ["en:glass", "en:clear-glass", "en:green-glass", "en:brown-glass", "en:wood"]),
        ("en:can", ["en:paper", "en:cardboard", "en:glass", "en:clear-glass"]),
        ("en:jar", ["en:paper", "en:cardboard"]),
    ]

    static func anomalies(in product: ScannedProduct) -> [PackagingAnomaly] {
        guard !product.components.isEmpty else { return [.noComponents] }

        var found: [PackagingAnomaly] = []

        // A single component is the commonest shape of thin data, and it is the one that
        // undercuts the whole premise: a product reported as one part cannot be
        // decomposed into several.
        if product.components.count == 1 {
            found.append(.singleComponent)
        }

        var counts: [String: (shape: TaxonomyID?, material: TaxonomyID, count: Int)] = [:]
        for component in product.components {
            let key = "\(component.shape?.value ?? "-")|\(component.material.value)"
            let existing = counts[key]
            counts[key] = (component.shape, component.material, (existing?.count ?? 0) + 1)

            if !MaterialTaxonomy.isKnown(component.material) {
                let anomaly = PackagingAnomaly.unknownMaterial(component.material)
                if !found.contains(anomaly) { found.append(anomaly) }
            }

            if let shape = component.shape,
               implausible.contains(where: { $0.shape == shape && $0.materials.contains(component.material) }) {
                found.append(.implausiblePairing(shape: shape, material: component.material))
            }
        }

        for entry in counts.values where entry.count > 1 {
            found.append(
                .repeatedComponent(shape: entry.shape, material: entry.material, times: entry.count)
            )
        }

        return found
    }
}
