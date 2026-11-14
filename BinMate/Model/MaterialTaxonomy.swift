import Foundation

/// A trimmed copy of the Open Food Facts packaging-material hierarchy.
///
/// The hierarchy is what lets a city ruleset stay short. Kraków does not need a line
/// for every one of the forty-odd plastics in the taxonomy: it writes one rule for
/// `en:plastic`, and a bottle made of `en:rpet-recycled-polyethylene-terephthalate`
/// still resolves by walking up to its ancestor. Cities that *do* treat a specific
/// polymer differently simply add the more specific rule, which wins.
enum MaterialTaxonomy {
    /// Child to parent edges. Materials absent from this table are treated as roots.
    private static let parents: [TaxonomyID: TaxonomyID] = [
        // Plastics
        "en:pet-polyethylene-terephthalate": "en:plastic",
        "en:rpet-recycled-polyethylene-terephthalate": "en:pet-polyethylene-terephthalate",
        "en:opaque-pet": "en:pet-polyethylene-terephthalate",
        "en:hdpe-high-density-polyethylene": "en:plastic",
        "en:ldpe-low-density-polyethylene": "en:plastic",
        "en:pp-polypropylene": "en:plastic",
        "en:ps-polystyrene": "en:plastic",
        "en:eps-expanded-polystyrene": "en:ps-polystyrene",
        "en:pvc-polyvinyl-chloride": "en:plastic",
        "en:other-plastics": "en:plastic",
        "en:bio-based-plastic": "en:plastic",
        "en:pla-polylactic-acid": "en:bio-based-plastic",

        // Fibre
        "en:paper": "en:paper-or-cardboard",
        "en:coated-paper": "en:paper",
        "en:kraft-paper": "en:paper",
        "en:cardboard": "en:paper-or-cardboard",
        "en:corrugated-cardboard": "en:cardboard",
        "en:non-corrugated-cardboard": "en:cardboard",
        "en:moulded-fibre": "en:paper-or-cardboard",

        // Glass, sorted by colour because some cities separate the colours
        "en:clear-glass": "en:glass",
        "en:green-glass": "en:glass",
        "en:brown-glass": "en:glass",

        // Metals
        "en:aluminium": "en:metal",
        "en:steel": "en:metal",
        "en:tinplate": "en:steel",

        // Composites, the ones people get wrong most often
        "en:tetra-pak": "en:beverage-carton",
        "en:beverage-carton": "en:composite",
        "en:plastic-and-aluminium-composite": "en:composite",
        "en:paper-and-plastic-composite": "en:composite",

        // Other
        "en:cork": "en:wood",
    ]

    private static let displayNames: [TaxonomyID: String] = [
        "en:plastic": "Plastic",
        "en:pet-polyethylene-terephthalate": "PET plastic",
        "en:rpet-recycled-polyethylene-terephthalate": "Recycled PET",
        "en:opaque-pet": "Opaque PET",
        "en:hdpe-high-density-polyethylene": "HDPE plastic",
        "en:ldpe-low-density-polyethylene": "LDPE plastic",
        "en:pp-polypropylene": "PP plastic",
        "en:ps-polystyrene": "PS plastic",
        "en:eps-expanded-polystyrene": "Expanded polystyrene",
        "en:pvc-polyvinyl-chloride": "PVC plastic",
        "en:other-plastics": "Mixed plastic",
        "en:bio-based-plastic": "Bio-based plastic",
        "en:pla-polylactic-acid": "PLA bioplastic",
        "en:paper-or-cardboard": "Paper or cardboard",
        "en:paper": "Paper",
        "en:coated-paper": "Coated paper",
        "en:kraft-paper": "Kraft paper",
        "en:cardboard": "Cardboard",
        "en:corrugated-cardboard": "Corrugated cardboard",
        "en:non-corrugated-cardboard": "Cardboard",
        "en:moulded-fibre": "Moulded fibre",
        "en:glass": "Glass",
        "en:clear-glass": "Clear glass",
        "en:green-glass": "Green glass",
        "en:brown-glass": "Brown glass",
        "en:metal": "Metal",
        "en:aluminium": "Aluminium",
        "en:steel": "Steel",
        "en:tinplate": "Tinplate",
        "en:composite": "Composite",
        "en:beverage-carton": "Beverage carton",
        "en:tetra-pak": "Tetra Pak carton",
        "en:plastic-and-aluminium-composite": "Plastic and aluminium",
        "en:paper-and-plastic-composite": "Paper and plastic",
        "en:wood": "Wood",
        "en:cork": "Cork",
        "en:unknown": "Unidentified material",
    ]

    /// Spellings that turn up in contributed data but are not taxonomy entries.
    private static let aliases: [TaxonomyID: TaxonomyID] = [
        "en:pet": "en:pet-polyethylene-terephthalate",
        "en:pete": "en:pet-polyethylene-terephthalate",
        "en:hdpe": "en:hdpe-high-density-polyethylene",
        "en:ldpe": "en:ldpe-low-density-polyethylene",
        "en:pp": "en:pp-polypropylene",
        "en:ps": "en:ps-polystyrene",
        "en:pvc": "en:pvc-polyvinyl-chloride",
        "en:pla": "en:pla-polylactic-acid",
        "en:alu": "en:aluminium",
        "en:aluminum": "en:aluminium",
        "en:tin": "en:tinplate",
        "en:carton": "en:beverage-carton",
        "en:tetrapak": "en:tetra-pak",
        "en:plastique": "en:plastic",
        "en:verre": "en:glass",
    ]

    static let unknown: TaxonomyID = "en:unknown"

    /// Resolves contributed spellings onto a canonical taxonomy entry.
    static func canonical(_ id: TaxonomyID) -> TaxonomyID {
        aliases[id] ?? id
    }

    /// The material itself followed by each ancestor, nearest first.
    ///
    /// `rPET` yields `[rPET, PET, plastic]`, which is exactly the order a rule lookup
    /// should try: the most specific rule a city wrote should always win.
    static func ancestry(of id: TaxonomyID) -> [TaxonomyID] {
        var chain = [canonical(id)]
        var seen: Set<TaxonomyID> = [chain[0]]

        while let parent = parents[chain[chain.count - 1]] {
            // The table is hand written, so refuse to loop forever if an edge is wrong.
            guard seen.insert(parent).inserted else { break }
            chain.append(parent)
        }
        return chain
    }

    static func displayName(for id: TaxonomyID) -> String {
        displayNames[canonical(id)] ?? canonical(id).humanized
    }

    /// Materials offered in the manual picker, ordered by how often household packaging
    /// actually uses them rather than alphabetically.
    static let pickerMaterials: [TaxonomyID] = [
        "en:pet-polyethylene-terephthalate",
        "en:hdpe-high-density-polyethylene",
        "en:ldpe-low-density-polyethylene",
        "en:pp-polypropylene",
        "en:ps-polystyrene",
        "en:other-plastics",
        "en:pla-polylactic-acid",
        "en:paper",
        "en:cardboard",
        "en:coated-paper",
        "en:clear-glass",
        "en:green-glass",
        "en:brown-glass",
        "en:aluminium",
        "en:steel",
        "en:beverage-carton",
        "en:composite",
        "en:wood",
        "en:cork",
    ]
}

/// Packaging component shapes. Shapes never form a hierarchy in BinMate; a rule either
/// names the shape or applies to every shape of that material.
enum ShapeTaxonomy {
    private static let displayNames: [TaxonomyID: String] = [
        "en:bottle": "Bottle",
        "en:cap": "Cap",
        "en:lid": "Lid",
        "en:label": "Label",
        "en:sleeve": "Sleeve",
        "en:film": "Film",
        "en:wrapper": "Wrapper",
        "en:tray": "Tray",
        "en:box": "Box",
        "en:can": "Can",
        "en:jar": "Jar",
        "en:pot": "Pot",
        "en:cup": "Cup",
        "en:bag": "Bag",
        "en:seal": "Seal",
        "en:straw": "Straw",
        "en:net": "Net",
        "en:card": "Card",
        "en:spout": "Spout",
    ]

    /// SF Symbol per shape, used on the component cards.
    private static let symbols: [TaxonomyID: String] = [
        "en:bottle": "waterbottle",
        "en:cap": "circle.circle",
        "en:lid": "circle.dashed",
        "en:label": "tag",
        "en:sleeve": "doc.plaintext",
        "en:film": "rectangle.dashed",
        "en:wrapper": "rectangle.dashed",
        "en:tray": "tray",
        "en:box": "shippingbox",
        "en:can": "cylinder",
        "en:jar": "cylinder.split.1x2",
        "en:pot": "cup.and.saucer",
        "en:cup": "cup.and.saucer",
        "en:bag": "bag",
        "en:seal": "seal",
        "en:straw": "line.diagonal",
        "en:net": "grid",
        "en:card": "rectangle",
        "en:spout": "drop",
    ]

    static func displayName(for id: TaxonomyID?) -> String {
        guard let id else { return "Component" }
        return displayNames[id] ?? id.humanized
    }

    static func symbol(for id: TaxonomyID?) -> String {
        guard let id, let symbol = symbols[id] else { return "cube" }
        return symbol
    }

    /// Shapes offered in the manual picker.
    static let pickerShapes: [TaxonomyID] = [
        "en:bottle", "en:cap", "en:lid", "en:label", "en:sleeve",
        "en:film", "en:wrapper", "en:tray", "en:box", "en:can",
        "en:jar", "en:pot", "en:cup", "en:bag", "en:seal",
    ]
}
