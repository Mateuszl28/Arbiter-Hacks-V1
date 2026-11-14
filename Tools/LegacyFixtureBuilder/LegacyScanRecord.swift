import Foundation
import SwiftData

// A copy of ScanRecord as it existed BEFORE the take-back work: no `returnedAt`, and no
// `id` of its own. Used only to cut a fixture store in the old shape, so the migration
// check tests old-schema -> new-schema rather than new -> new.
//
// The class name must match, because SwiftData keys its entity on the type name.
@Model
final class ScanRecord {
    var scannedAt: Date = Date()
    var barcode: String?
    var productName: String = ""
    var brand: String?
    var imageURLString: String?
    var cityID: String = ""
    var cityName: String = ""
    var componentsJSON: Data = Data()
    var originRaw: String = "manual"

    init(
        scannedAt: Date,
        barcode: String?,
        productName: String,
        brand: String?,
        cityID: String,
        cityName: String,
        componentsJSON: Data,
        originRaw: String
    ) {
        self.scannedAt = scannedAt
        self.barcode = barcode
        self.productName = productName
        self.brand = brand
        self.cityID = cityID
        self.cityName = cityName
        self.componentsJSON = componentsJSON
        self.originRaw = originRaw
    }
}
