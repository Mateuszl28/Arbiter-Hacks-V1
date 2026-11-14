import Foundation

/// The bundled sample products.
///
/// These exist so that nothing about BinMate depends on a working network or a working
/// camera: the simulator can demonstrate the whole flow, and a demo recorded in a room
/// with bad wifi behaves exactly the same as one recorded at a desk.
struct SampleProducts: Sendable {
    let products: [ScannedProduct]
    let problems: [String]

    static func loadBundled(bundle: Bundle = .main) -> SampleProducts {
        guard let url = bundle.url(forResource: "DemoProducts", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return SampleProducts(products: [], problems: ["DemoProducts.json is missing from the bundle"])
        }

        do {
            let file = try JSONDecoder().decode(SampleFile.self, from: data)
            return SampleProducts(
                products: file.products.map(\.asScannedProduct),
                problems: []
            )
        } catch {
            return SampleProducts(
                products: [],
                problems: ["DemoProducts.json: \(error.localizedDescription)"]
            )
        }
    }

    func product(barcode: String) -> ScannedProduct? {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return products.first { $0.barcode == trimmed }
    }

    private struct SampleFile: Decodable {
        var products: [SampleProduct]
    }

    private struct SampleProduct: Decodable {
        var barcode: String
        var name: String
        var brand: String?
        var components: [PackagingComponent]

        var asScannedProduct: ScannedProduct {
            ScannedProduct(
                barcode: barcode,
                name: name,
                brand: brand,
                imageURL: nil,
                components: components,
                origin: .offlineSample
            )
        }
    }
}
