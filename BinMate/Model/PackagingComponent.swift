import Foundation

/// One physical part of a product's packaging.
///
/// This is the unit BinMate reasons about, and the reason its answers differ from the
/// usual "point your camera at rubbish" app. A yogurt pot is not one piece of waste;
/// it is a polystyrene pot, an aluminium lid and a cardboard sleeve, and in most cities
/// those three go to three different places.
struct PackagingComponent: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    /// What the part is: bottle, cap, label. `nil` when upstream data only names a material.
    var shape: TaxonomyID?
    /// What the part is made of, as a taxonomy id.
    var material: TaxonomyID
    /// How many of this part come with one product, e.g. six yogurt pots in a multipack.
    var numberOfUnits: Int
    /// Free text weight or volume from Open Food Facts, shown as-is when present.
    var quantityPerUnit: String?
    /// Open Food Facts' own recycling note. Kept separate from the city verdict so the
    /// two are never confused: this is a global hint, the verdict is local law.
    var upstreamRecyclingHint: String?

    init(
        id: UUID = UUID(),
        shape: TaxonomyID? = nil,
        material: TaxonomyID,
        numberOfUnits: Int = 1,
        quantityPerUnit: String? = nil,
        upstreamRecyclingHint: String? = nil
    ) {
        self.id = id
        self.shape = shape
        self.material = MaterialTaxonomy.canonical(material)
        self.numberOfUnits = max(1, numberOfUnits)
        self.quantityPerUnit = quantityPerUnit
        self.upstreamRecyclingHint = upstreamRecyclingHint
    }

    // MARK: - Lenient decoding
    //
    // The same type is decoded from three places: bundled sample products, the on-device
    // cache, and hand-edited JSON. Only the cache ever writes an `id`, and only
    // Open Food Facts is sloppy about number types, so everything optional gets a
    // sensible default rather than failing the whole file.

    private enum CodingKeys: String, CodingKey {
        case id, shape, material, numberOfUnits, quantityPerUnit, upstreamRecyclingHint
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            shape: try container.decodeIfPresent(TaxonomyID.self, forKey: .shape),
            material: try container.decode(TaxonomyID.self, forKey: .material),
            numberOfUnits: try container.decodeIfPresent(Int.self, forKey: .numberOfUnits) ?? 1,
            quantityPerUnit: try container.decodeIfPresent(String.self, forKey: .quantityPerUnit),
            upstreamRecyclingHint: try container.decodeIfPresent(String.self, forKey: .upstreamRecyclingHint)
        )
    }

    var materialName: String { MaterialTaxonomy.displayName(for: material) }
    var shapeName: String { ShapeTaxonomy.displayName(for: shape) }
    var symbolName: String { ShapeTaxonomy.symbol(for: shape) }

    /// "Cap · PP plastic", or just the material when the shape is unknown.
    var headline: String {
        shape == nil ? materialName : "\(shapeName) · \(materialName)"
    }
}

/// A product resolved from a barcode, or assembled by hand when there is no barcode.
struct ScannedProduct: Identifiable, Hashable, Codable, Sendable {
    enum Origin: String, Codable, Sendable {
        /// Fetched live from the Open Food Facts API.
        case openFoodFacts
        /// Read from the bundled sample set, so the app works with no network at all.
        case offlineSample
        /// Previously fetched and kept on device.
        case cache
        /// Described by the user through the manual picker.
        case manual
    }

    var id: String { barcode ?? name }
    var barcode: String?
    var name: String
    var brand: String?
    var imageURL: URL?
    var components: [PackagingComponent]
    var origin: Origin

    /// Open Food Facts frequently has a product but no structured packaging data. That is
    /// a different outcome from "barcode not found" and the UI handles it differently.
    var hasPackagingData: Bool { !components.isEmpty }

    var displayTitle: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(brand) \(name)"
    }
}
