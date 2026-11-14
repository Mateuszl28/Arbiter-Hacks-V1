import Foundation

/// What changed about a product's packaging since it was last scanned.
///
/// Producers change packaging and rarely announce it. A bottle that was glass last year
/// is PET now; a cap switches polymer; a paper label becomes a plastic sleeve. BinMate
/// already keeps every scan, so it is in a position to notice — and noticing matters
/// because a changed material can change the bin, which is precisely the moment someone
/// is relying on a habit formed last time.
///
/// Comparison is by *part* rather than by position: Open Food Facts contributors list
/// components in no particular order, so matching on index would report nonsense changes
/// every time somebody reordered a record.
struct PackagingDiff: Sendable {
    enum Change: Sendable, Hashable {
        /// A part that was not there before.
        case added(PackagingComponent)
        /// A part that has gone.
        case removed(PackagingComponent)
        /// Same part, different material. The one that can move a bin.
        case materialChanged(shape: TaxonomyID?, from: TaxonomyID, to: TaxonomyID)
        /// Same part and material, different quantity — a six-pack became a four-pack.
        case countChanged(shape: TaxonomyID?, material: TaxonomyID, from: Int, to: Int)

        var summary: String {
            switch self {
            case .added(let component):
                "\(component.headline) is new"
            case .removed(let component):
                "\(component.headline) is gone"
            case .materialChanged(let shape, let from, let to):
                "\(ShapeTaxonomy.displayName(for: shape)) changed from \(MaterialTaxonomy.displayName(for: from)) to \(MaterialTaxonomy.displayName(for: to))"
            case .countChanged(let shape, _, let from, let to):
                "\(ShapeTaxonomy.displayName(for: shape)) went from \(from) to \(to)"
            }
        }
    }

    var changes: [Change]

    var isEmpty: Bool { changes.isEmpty }

    /// Only the changes that could move something to a different bin. A count change
    /// never does; a material change usually can.
    func binAffecting(under engine: RulesEngine) -> [Change] {
        changes.filter { change in
            switch change {
            case .added, .removed:
                return true
            case .materialChanged(let shape, let from, let to):
                let before = engine.verdict(for: PackagingComponent(shape: shape, material: from))
                let after = engine.verdict(for: PackagingComponent(shape: shape, material: to))
                return before.stream.id != after.stream.id
            case .countChanged:
                return false
            }
        }
    }

    /// Compares two scans of the same product.
    static func between(
        previous: [PackagingComponent],
        current: [PackagingComponent]
    ) -> PackagingDiff {
        var changes: [Change] = []

        // Index by part. Several components can share a shape — two labels, say — so the
        // value is a list and matching consumes from it.
        var previousByShape: [TaxonomyID?: [PackagingComponent]] = [:]
        for component in previous {
            previousByShape[component.shape, default: []].append(component)
        }

        for component in current {
            guard var candidates = previousByShape[component.shape], !candidates.isEmpty else {
                changes.append(.added(component))
                continue
            }

            // Prefer the candidate with the same material, so a genuine material change
            // is reported as a change rather than as an add plus a remove.
            let index = candidates.firstIndex { $0.material == component.material } ?? 0
            let match = candidates.remove(at: index)
            previousByShape[component.shape] = candidates

            if match.material != component.material {
                changes.append(
                    .materialChanged(shape: component.shape, from: match.material, to: component.material)
                )
            } else if match.numberOfUnits != component.numberOfUnits {
                changes.append(
                    .countChanged(
                        shape: component.shape,
                        material: component.material,
                        from: match.numberOfUnits,
                        to: component.numberOfUnits
                    )
                )
            }
        }

        // Anything left unmatched has gone.
        for leftovers in previousByShape.values {
            for component in leftovers { changes.append(.removed(component)) }
        }

        return PackagingDiff(changes: changes)
    }
}
