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
