import Foundation
import OSLog

enum ProductLookupError: LocalizedError, Equatable {
    case notFound(barcode: String)
    case noPackagingData(product: String)
    case offline
    case server(status: Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notFound(let barcode):
            "No product found for barcode \(barcode)."
        case .noPackagingData(let product):
            "Open Food Facts knows \(product), but nobody has described its packaging yet."
        case .offline:
            "No internet connection."
        case .server(let status):
            "Open Food Facts returned an error (HTTP \(status))."
        case .malformedResponse:
            "Open Food Facts returned something unexpected."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notFound:
            "You can describe the packaging yourself — it takes a few taps."
        case .noPackagingData:
            "Describe the parts yourself and BinMate will still sort them."
        case .offline:
            "Sample products and all sorting rules work offline."
        case .server, .malformedResponse:
            "Try again, or describe the packaging by hand."
        }
    }
}

/// Reads product packaging from the Open Food Facts API.
///
/// Open Food Facts is a crowd-sourced database, which means two things in practice: the
/// coverage is remarkable, and the data is inconsistent. Every field here is treated as
/// optional and every number is accepted as either a number or a string, because all of
/// those variations genuinely occur in the live dataset.
actor OpenFoodFactsClient {
    private let session: URLSession
    private let logger = Logger(subsystem: "app.binmate", category: "OpenFoodFacts")

    /// Open Food Facts asks every client to identify itself, and blocks those that don't.
    private static let userAgent = "BinMate/1.0 (iOS; packaging sorting assistant)"

    private static let fields = [
        "product_name", "product_name_en", "generic_name", "brands",
        "image_front_small_url", "packagings", "packaging_text",
    ].joined(separator: ",")

    init(session: URLSession = .shared) {
        self.session = session
    }

    func product(barcode: String) async throws -> ScannedProduct {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(trimmed).json") else {
            throw ProductLookupError.malformedResponse
        }
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        guard let url = components.url else { throw ProductLookupError.malformedResponse }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw ProductLookupError.offline
        } catch {
            logger.error("Lookup failed for \(trimmed, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ProductLookupError.offline
        }

        if let http = response as? HTTPURLResponse {
            // 404 is how the API reports an unknown barcode in some deployments.
            if http.statusCode == 404 { throw ProductLookupError.notFound(barcode: trimmed) }
            guard (200..<300).contains(http.statusCode) else {
                throw ProductLookupError.server(status: http.statusCode)
            }
        }

        let payload: ProductResponse
        do {
            payload = try JSONDecoder().decode(ProductResponse.self, from: data)
        } catch {
            logger.error("Decode failed for \(trimmed, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw ProductLookupError.malformedResponse
        }

        guard payload.status == 1, let product = payload.product else {
            throw ProductLookupError.notFound(barcode: trimmed)
        }

        let name = product.bestName ?? "Unnamed product"
        let components0 = product.packagings?.compactMap(\.asPackagingComponent) ?? []

        // A product with no packaging breakdown is a distinct, recoverable outcome:
        // the manual picker can still produce a useful answer.
        guard !components0.isEmpty else {
            throw ProductLookupError.noPackagingData(product: name)
        }

        return ScannedProduct(
            barcode: trimmed,
            name: name,
            brand: product.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) },
            imageURL: product.image_front_small_url.flatMap(URL.init(string:)),
            components: components0,
            origin: .openFoodFacts
        )
    }
}

// MARK: - Wire format

private struct ProductResponse: Decodable {
    var status: Int?
    var product: ProductDTO?
}

private struct ProductDTO: Decodable {
    var product_name: String?
    var product_name_en: String?
    var generic_name: String?
    var brands: String?
    var image_front_small_url: String?
    var packagings: [PackagingDTO]?
    var packaging_text: String?

    /// Prefers an English name, because the whole interface is English.
    var bestName: String? {
        [product_name_en, product_name, generic_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct PackagingDTO: Decodable {
    var material: String?
    var shape: String?
    var number_of_units: LenientInt?
    var quantity_per_unit: String?
    var recycling: String?

    /// Drops entries with no material. Those exist in the dataset and carry no
    /// information BinMate can act on; the manual picker is the better answer.
    var asPackagingComponent: PackagingComponent? {
        guard let material, !material.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return PackagingComponent(
            shape: shape.flatMap { $0.isEmpty ? nil : TaxonomyID($0) },
            material: TaxonomyID(material),
            numberOfUnits: number_of_units?.value ?? 1,
            quantityPerUnit: quantity_per_unit.flatMap { $0.isEmpty ? nil : $0 },
            upstreamRecyclingHint: recycling.flatMap { $0.isEmpty ? nil : TaxonomyID($0).humanized }
        )
    }
}

/// `number_of_units` arrives as `2`, `"2"` or `"2 units"` depending on who typed it in.
private struct LenientInt: Decodable {
    let value: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = Int(double)
        } else if let string = try? container.decode(String.self),
                  let int = Int(string.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) {
            value = int
        } else {
            value = 1
        }
    }
}
