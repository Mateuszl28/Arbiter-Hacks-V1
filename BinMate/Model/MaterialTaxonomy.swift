import Foundation

/// The packaging material tree.
///
/// This used to be hand written, and hand writing it failed in the way hand written
/// reference data always fails: the identifiers looked right and were not real.
/// `en:pp-polypropylene` was a guess — the published entry is `en:pp-5-polypropylene`,
/// with the recycling code in the middle of the name. Seven of those guesses covered the
/// seven standard plastics, so every plastic with good data matched nothing and fell
/// into residual waste, with a confident explanation attached.
///
/// The tree is now read from the Open Food Facts taxonomy (see `OFFTaxonomy`, generated
/// by Tools/generate-taxonomy.py) and `./Tools/verify-taxonomy.sh` fails if any entry in
/// it cannot be placed. What remains by hand is only what cannot be derived: the handful
/// of concepts the taxonomy lacks, the places BinMate deliberately disagrees with it,
/// and wording for the UI. Each of those is declared below rather than folded in
/// quietly, because a reader is entitled to know which parts of the tree are ours.
enum MaterialTaxonomy {
    /// Materials the published taxonomy has no entry for.
    ///
    /// Moulded fibre is what an egg box is made of and is not in the taxonomy at all.
    /// Cork is in it, but as a root, and for disposal purposes it behaves like wood.
    private static let extensions: [TaxonomyID: [TaxonomyID]] = [
        "en:coated-paper": ["en:paper"],
        "en:moulded-fibre": ["en:paper-or-cardboard"],
        "en:cork": ["en:wood"],
    ]

    /// Where BinMate deliberately departs from the published tree.
    ///
    /// Open Food Facts files a Tetra Pak directly under composite material, so it would
    /// never reach a city's beverage-carton rule — and a beverage carton is precisely the
    /// thing cities bother to write a separate rule for. Its real place is the code-84
    /// paper/plastic/aluminium concept, which is what a Tetra Pak is.
    private static let divergences: [TaxonomyID: [TaxonomyID]] = [
        "en:tetra-pak": ["en:paper-and-cardboard-plastic-aluminium"],
    ]

    private static let parents: [TaxonomyID: [TaxonomyID]] =
        OFFTaxonomy.materialParents
            .merging(extensions) { _, mine in mine }
            .merging(divergences) { _, mine in mine }

    /// Wording for the screen, where the published name is unusable as a chip.
    ///
    /// "PET 1 - Polyethylene terephthalate" is correct and nobody wants to read it on a
    /// bin card; "composite material" is lowercase in the source. Everything not listed
    /// here uses the published English name, so this stays short on purpose.
    private static let displayOverrides: [TaxonomyID: String] = [
        "en:pet-1-polyethylene-terephthalate": "PET plastic",
        "en:rpet-recycled-polyethylene-terephthalate": "Recycled PET",
        "en:pet-opaque": "Opaque PET",
        "en:hdpe-2-high-density-polyethylene": "HDPE plastic",
        "en:ldpe-4-low-density-polyethylene": "LDPE plastic",
        "en:pp-5-polypropylene": "PP plastic",
        "en:ps-6-polystyrene": "PS plastic",
        "en:eps-expanded-polystyrene": "Expanded polystyrene",
        "en:pvc-3-polyvinyl-chloride": "PVC plastic",
        "en:o-7-other-plastics": "Mixed plastic",
        "en:pla-polylactic-acid": "PLA bioplastic",
        "en:non-corrugated-cardboard": "Cardboard",
        "en:composite-material": "Composite",
        "en:paper-and-cardboard-plastic-aluminium": "Beverage carton",
        "en:tetra-pak": "Tetra Pak carton",
        "en:plastic-aluminium": "Plastic and aluminium",
        "en:tin-plated-steel": "Tinplate",
        "en:coated-paper": "Coated paper",
        "en:moulded-fibre": "Moulded fibre",
        "en:unknown": "Unidentified material",
    ]

    /// Shorthands a person might type, or that older records in this app contain.
    ///
    /// Deliberately short. An earlier version of this table carried two dozen invented
    /// recycling-code spellings — `en:pap-22-paper`, `en:alu-41-aluminium`,
    /// `en:gl-70-clear-glass` — that read as authoritative and that the API never
    /// returns, because the real codes are filed as `xx:80-c-alu` and come out of the
    /// generated tree. Guessing at upstream spellings is what this whole file is now
    /// arranged to avoid, so nothing goes in here that has not been seen in real data or
    /// typed by a real person.
    private static let aliases: [TaxonomyID: TaxonomyID] = [
        "en:pet": "en:pet-1-polyethylene-terephthalate",
        "en:pete": "en:pet-1-polyethylene-terephthalate",
        "en:hdpe": "en:hdpe-2-high-density-polyethylene",
        "en:ldpe": "en:ldpe-4-low-density-polyethylene",
        "en:pp": "en:pp-5-polypropylene",
        "en:ps": "en:ps-6-polystyrene",
        "en:pvc": "en:pvc-3-polyvinyl-chloride",
        "en:pla": "en:pla-polylactic-acid",
        "en:alu": "en:aluminium",
        "en:aluminum": "en:aluminium",
        "en:tin": "en:tin-plated-steel",
        "en:carton": "en:paper-and-cardboard-plastic-aluminium",
        "en:tetrapak": "en:tetra-pak",
        "en:other-plastics": "en:o-7-other-plastics",
        "en:mixed-plastic": "en:mixed-plastics",
    ]

    /// Identifiers this app used itself, before the tree was derived from the published
    /// taxonomy.
    ///
    /// These are not guesses about upstream — they are BinMate's own history, and
    /// somebody's saved scans are written in them. Dropping them would turn every record
    /// in an existing install into "unrecognised material", which is a worse outcome than
    /// carrying fourteen lines. ./Tools/verify-store.sh opens a store written before the
    /// rename and fails if any of it stops resolving.
    private static let legacyIDs: [TaxonomyID: TaxonomyID] = [
        "en:pet-polyethylene-terephthalate": "en:pet-1-polyethylene-terephthalate",
        "en:hdpe-high-density-polyethylene": "en:hdpe-2-high-density-polyethylene",
        "en:ldpe-low-density-polyethylene": "en:ldpe-4-low-density-polyethylene",
        "en:pp-polypropylene": "en:pp-5-polypropylene",
        "en:ps-polystyrene": "en:ps-6-polystyrene",
        "en:pvc-polyvinyl-chloride": "en:pvc-3-polyvinyl-chloride",
        "en:bio-based-plastic": "en:biobased-plastic",
        "en:opaque-pet": "en:pet-opaque",
        "en:composite": "en:composite-material",
        "en:beverage-carton": "en:paper-and-cardboard-plastic-aluminium",
        "en:paper-and-plastic-composite": "en:paper-and-plastic",
        "en:plastic-and-aluminium-composite": "en:plastic-aluminium",
        "en:tinplate": "en:tin-plated-steel",
    ]

    static let unknown: TaxonomyID = "en:unknown"

    /// Resolves whatever arrived onto an entry this app can reason about.
    ///
    /// Four steps, cheapest first, and each one exists because real data needed it:
    /// a hand shorthand, the entry itself, the same entry written untidily, and finally
    /// the entry named in another language.
    static func canonical(_ id: TaxonomyID) -> TaxonomyID {
        if let alias = aliases[id] ?? legacyIDs[id] { return alias }
        if isDefined(id) { return id }

        // `fr:PP 5 - Polypropylène` normalises to `fr:pp-5---polypropylène`, which
        // matches nothing until the accents and the hyphen run are folded away.
        let folded = TaxonomyID("\(id.language):\(id.folded)")
        if let alias = aliases[folded] ?? legacyIDs[folded] { return alias }
        if isDefined(folded) { return folded }

        // A contributed term in another language. 1841 of these come straight out of the
        // taxonomy's own translations, so none of them is a guess.
        if let translated = OFFSynonyms.shared.material(for: folded) {
            return translated
        }

        // Contributors mislabel the language often enough to be worth one last try: the
        // same term as English, then as a bare term in any language that names it.
        let asEnglish = TaxonomyID("en:\(id.folded)")
        if isDefined(asEnglish) { return asEnglish }
        if let alias = aliases[asEnglish] { return alias }
        if let translated = OFFSynonyms.shared.materialInAnyLanguage(for: id.folded) {
            return translated
        }
        return id
    }

    /// Whether the tree actually contains this entry, before any resolution.
    private static func isDefined(_ id: TaxonomyID) -> Bool {
        OFFTaxonomy.materialNames[id] != nil
            || parents[id] != nil
            || displayOverrides[id] != nil
    }

    /// The material itself followed by each ancestor, nearest first.
    ///
    /// `rPET` yields `[rPET, PET, plastic]`, which is exactly the order a rule lookup
    /// should try: the most specific rule a city wrote should always win.
    ///
    /// The published taxonomy is a DAG rather than a tree — 27 materials have more than
    /// one parent, HDPE being both a polyethylene and a plastic. Following only the first
    /// parent would quietly decide which of a city's rules a material inherits, so this
    /// is a breadth-first walk: everything one hop away before anything two hops away,
    /// and the listed order breaks ties so the result is stable.
    static func ancestry(of id: TaxonomyID) -> [TaxonomyID] {
        let start = canonical(id)
        var chain = [start]
        var seen: Set<TaxonomyID> = [start]
        var queue = [start]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for parent in parents[current] ?? [] where seen.insert(parent).inserted {
                chain.append(parent)
                queue.append(parent)
            }
        }
        return chain
    }

    static func displayName(for id: TaxonomyID) -> String {
        let resolved = canonical(id)
        return displayOverrides[resolved]
            ?? OFFTaxonomy.materialNames[resolved]
            ?? resolved.humanized
    }

    /// Whether the taxonomy has ever heard of this material.
    ///
    /// Distinct from "has no rule": an unknown material means even the ancestry walk had
    /// nothing to climb, so the fallback was not a considered general rule but a shrug.
    /// The two deserve different wording, and a user can act on the difference.
    static func isKnown(_ id: TaxonomyID) -> Bool {
        isDefined(canonical(id))
    }

    /// Every identifier the hand written tables point at.
    ///
    /// Exists so ./Tools/verify-taxonomy.sh can prove that none of them is invented. The
    /// bug that produced this whole arrangement was a table full of plausible spellings
    /// that no published taxonomy contained, and the only durable defence against
    /// writing another one is a test that reads the source and disagrees.
    static var declaredTargets: [TaxonomyID] {
        Array(aliases.values)
            + Array(legacyIDs.values)
            + Array(divergences.values.joined())
            + Array(extensions.values.joined())
            + pickerMaterials
    }

    /// The concepts BinMate added itself, which verify-taxonomy is expected to find
    /// absent from the published taxonomy.
    static let declaredExtensions: [TaxonomyID] = ["en:coated-paper", "en:moulded-fibre", "en:unknown"]

    /// Materials offered in the manual picker, ordered by how often household packaging
    /// actually uses them rather than alphabetically.
    static let pickerMaterials: [TaxonomyID] = [
        "en:pet-1-polyethylene-terephthalate",
        "en:hdpe-2-high-density-polyethylene",
        "en:ldpe-4-low-density-polyethylene",
        "en:pp-5-polypropylene",
        "en:ps-6-polystyrene",
        "en:o-7-other-plastics",
        "en:pla-polylactic-acid",
        "en:paper",
        "en:cardboard",
        "en:coated-paper",
        "en:clear-glass",
        "en:green-glass",
        "en:brown-glass",
        "en:aluminium",
        "en:steel",
        "en:paper-and-cardboard-plastic-aluminium",
        "en:composite-material",
        "en:wood",
        "en:cork",
    ]
}

/// Packaging component shapes.
///
/// These used to be treated as flat — a rule either named the exact shape or applied to
/// every shape. The published taxonomy says otherwise: a screw cap is a bottle cap is a
/// lid-or-cap, and a bottle is a bottle-or-vial. Flat matching meant a city rule about
/// caps missed every `en:screw-cap` a real scan produced, which is the same failure the
/// materials had, one level down.
///
/// The names come from the same published taxonomy as the materials, for the same
/// reason. What stays by hand is the symbol for each shape, which is a drawing decision
/// no taxonomy can make, and short labels where the published name is a sentence.
enum ShapeTaxonomy {
    private static let displayOverrides: [TaxonomyID: String] = [
        "en:card": "Card",
        "en:packaging": "Packaging",
        "en:lid-or-cap": "Cap or lid",
        "en:bottle-or-vial": "Bottle",
        "en:drinking-straw": "Straw",
        "en:napkin": "Napkin",
    ]

    /// Shapes the published taxonomy has no entry for.
    ///
    /// A napkin is not packaging, which is presumably why it is absent — but San
    /// Francisco and New York both write a compost rule that turns on it, so BinMate
    /// carries it and says so here rather than inventing it quietly.
    private static let extensions: [TaxonomyID: [TaxonomyID]] = [
        "en:napkin": [],
    ]

    /// Shape identifiers this app used before the tree came from the source. Saved scans
    /// are written in them.
    private static let legacyIDs: [TaxonomyID: TaxonomyID] = [
        "en:cap": "en:lid-or-cap",
        "en:cup": "en:tumbler",
        "en:straw": "en:drinking-straw",
    ]

    /// SF Symbol per shape, used on the component cards.
    private static let symbols: [TaxonomyID: String] = [
        "en:bottle": "waterbottle",
        "en:lid-or-cap": "circle.circle",
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
        "en:tumbler": "cup.and.saucer",
        "en:bag": "bag",
        "en:seal": "seal",
        "en:drinking-straw": "line.diagonal",
        "en:net": "grid",
        "en:card": "rectangle",
        "en:spout": "drop",
    ]

    /// Terms seen in live product data that the taxonomy does not translate.
    ///
    /// The derived synonym table covers every language the taxonomy names, which is most
    /// of them — but it has no Spanish word for a tray, which is exactly why Open Food
    /// Facts stored `es:Bandeja` as raw text rather than matching it. Each line here was
    /// read off a real product, not imagined, and anything that could not be translated
    /// with confidence was left out: `fr:Papier métallisé` is in the data and is not in
    /// here, because metallised paper has no entry to map onto and inventing one is the
    /// mistake this file exists to stop making.
    private static let observedTerms: [TaxonomyID: TaxonomyID] = [
        "es:bandeja": "en:tray",
        "de:wickler": "en:wrapper",
    ]

    /// Shapes arrive in other languages exactly as materials do — `es:Bandeja` for a
    /// tray, `de:wickler` for a wrapper were both found in live data.
    static func canonical(_ id: TaxonomyID) -> TaxonomyID {
        if let legacy = legacyIDs[id] { return legacy }
        if OFFTaxonomy.shapeNames[id] != nil || extensions[id] != nil { return id }
        if let observed = observedTerms[TaxonomyID("\(id.language):\(id.folded)")] {
            return observed
        }

        let folded = TaxonomyID("\(id.language):\(id.folded)")
        if OFFTaxonomy.shapeNames[folded] != nil { return folded }
        if let translated = OFFSynonyms.shared.shape(for: folded) { return translated }

        let asEnglish = TaxonomyID("en:\(id.folded)")
        if OFFTaxonomy.shapeNames[asEnglish] != nil { return asEnglish }
        if let translated = OFFSynonyms.shared.shapeInAnyLanguage(for: id.folded) {
            return translated
        }
        return id
    }

    /// The shape itself followed by each broader shape, nearest first — the same walk
    /// the materials use, and for the same reason: the most specific rule a city wrote
    /// should win, but a rule about caps should still catch a screw cap.
    static func ancestry(of id: TaxonomyID) -> [TaxonomyID] {
        let start = canonical(id)
        var chain = [start]
        var seen: Set<TaxonomyID> = [start]
        var queue = [start]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for parent in OFFTaxonomy.shapeParents[current] ?? [] where seen.insert(parent).inserted {
                chain.append(parent)
                queue.append(parent)
            }
        }
        return chain
    }

    static func displayName(for id: TaxonomyID?) -> String {
        guard let id else { return "Component" }
        let resolved = canonical(id)
        return displayOverrides[resolved]
            ?? OFFTaxonomy.shapeNames[resolved].map(capitalisedFirst)
            ?? resolved.humanized
    }

    /// The published names are inconsistently capitalised — "Tumbler" next to "card".
    private static func capitalisedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func symbol(for id: TaxonomyID?) -> String {
        guard let id, let symbol = symbols[canonical(id)] else { return "cube" }
        return symbol
    }

    /// Every shape identifier the hand written tables point at, for verify-taxonomy.
    static var declaredTargets: [TaxonomyID] {
        Array(observedTerms.values) + Array(legacyIDs.values)
            + Array(displayOverrides.keys) + Array(symbols.keys) + pickerShapes
    }

    /// The shapes BinMate adds itself, which verify-taxonomy expects to be absent
    /// upstream.
    static let declaredExtensions: [TaxonomyID] = ["en:napkin"]

    /// Shapes offered in the manual picker.
    static let pickerShapes: [TaxonomyID] = [
        "en:bottle", "en:lid-or-cap", "en:lid", "en:label", "en:sleeve",
        "en:film", "en:wrapper", "en:tray", "en:box", "en:can",
        "en:jar", "en:pot", "en:tumbler", "en:bag", "en:seal",
    ]
}
