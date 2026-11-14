import Foundation
import SwiftData

/// A product the user has sorted, kept on device.
///
/// History doubles as the offline cache: if a barcode has been looked up once, its
/// packaging breakdown is already here, so the second scan needs no network. That is why
/// the components are stored rather than just a reference to the barcode.
@Model
final class ScanRecord {
    #Index<ScanRecord>([\.scannedAt], [\.barcode])

    // Deliberately no `id` attribute of our own.
    //
    // An earlier version added `var id: UUID = UUID()` so the engine could refer to
    // records without importing SwiftData. Inspecting the store afterwards showed the
    // table had been recreated and every existing row dropped: a lightweight migration
    // cannot invent a distinct value for a new non-optional attribute, so it starts
    // over. On a real update that is silent data loss. The engine takes an opaque key
    // supplied by the caller instead, and `persistentModelID` serves perfectly well.
    var scannedAt: Date = Date()
    var barcode: String?
    var productName: String = ""
    var brand: String?
    var imageURLString: String?
    /// Which city's rules were in force at the time. Kept so history stays truthful
    /// after the user moves or travels — a scan made in Berlin is not relabelled.
    var cityID: String = ""
    var cityName: String = ""
    /// `[PackagingComponent]` as JSON. SwiftData can't store the array directly, and
    /// JSON keeps the record readable if the schema ever needs migrating by hand.
    var componentsJSON: Data = Data()
    var originRaw: String = ScannedProduct.Origin.manual.rawValue
    /// When the user took this one back — to a deposit machine or a drop-off point.
    /// Optional with a default so the store migrates without ceremony.
    var returnedAt: Date?

    init(product: ScannedProduct, city: CityRuleset, scannedAt: Date = Date()) {
        self.scannedAt = scannedAt
        self.barcode = product.barcode
        self.productName = product.name
        self.brand = product.brand
        self.imageURLString = product.imageURL?.absoluteString
        self.cityID = city.id
        self.cityName = city.displayName
        self.componentsJSON = (try? JSONEncoder().encode(product.components)) ?? Data()
        self.originRaw = product.origin.rawValue
    }

    /// Replaces the recorded packaging with a user correction. The timestamp and city
    /// stay as they were: the scan still happened when and where it happened.
    func update(with product: ScannedProduct) {
        productName = product.name
        brand = product.brand
        componentsJSON = (try? JSONEncoder().encode(product.components)) ?? componentsJSON
        originRaw = product.origin.rawValue
    }

    var components: [PackagingComponent] {
        (try? JSONDecoder().decode([PackagingComponent].self, from: componentsJSON)) ?? []
    }

    var origin: ScannedProduct.Origin {
        ScannedProduct.Origin(rawValue: originRaw) ?? .manual
    }

    /// Rebuilds the value type, so a history row can be re-sorted against any city.
    var product: ScannedProduct {
        ScannedProduct(
            barcode: barcode,
            name: productName,
            brand: brand,
            imageURL: imageURLString.flatMap(URL.init(string:)),
            components: components,
            origin: origin
        )
    }

    var displayTitle: String {
        guard let brand, !brand.isEmpty else { return productName }
        return "\(brand) \(productName)"
    }
}
