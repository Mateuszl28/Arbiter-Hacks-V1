import Foundation
import SwiftData

/// Turns a barcode into a product, choosing between the network, the on-device history
/// and the bundled samples.
///
/// The lookup order is deliberately visible to the user rather than hidden. In normal
/// mode BinMate prefers live data and degrades gracefully; in offline demo mode it never
/// touches the network at all. Either way the result carries its `origin`, and the UI
/// always says where an answer came from — a scan that silently served a bundled sample
/// as if it were live data would be a lie, however convenient.
@MainActor
struct ProductResolver {
    var client: OpenFoodFactsClient
    var samples: SampleProducts
    var context: ModelContext
    /// When true, no network request is ever made.
    var offlineOnly: Bool

    func resolve(barcode: String) async throws -> ScannedProduct {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)

        if offlineOnly {
            if let sample = samples.product(barcode: trimmed) { return sample }
            if let cached = cachedProduct(barcode: trimmed) { return cached }
            throw ProductLookupError.notFound(barcode: trimmed)
        }

        do {
            return try await client.product(barcode: trimmed)
        } catch let error as ProductLookupError {
            // Fall back only for failures that are about reaching the service. A genuine
            // "this barcode is not in the database" answer is information, not a failure,
            // and must not be papered over with a sample product.
            switch error {
            case .offline, .server, .malformedResponse:
                if let cached = cachedProduct(barcode: trimmed) { return cached }
                if let sample = samples.product(barcode: trimmed) { return sample }
                throw error
            case .notFound, .noPackagingData:
                if let sample = samples.product(barcode: trimmed) { return sample }
                throw error
            }
        }
    }

    /// Most recent history entry for this barcode, replayed as a cache hit.
    private func cachedProduct(barcode: String) -> ScannedProduct? {
        var descriptor = FetchDescriptor<ScanRecord>(
            predicate: #Predicate { $0.barcode == barcode },
            sortBy: [SortDescriptor(\.scannedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let record = try? context.fetch(descriptor).first,
              !record.components.isEmpty else { return nil }

        var product = record.product
        product.origin = .cache
        return product
    }
}
