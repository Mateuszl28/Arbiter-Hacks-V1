import Foundation
import Vision
import OSLog

/// Identifies likely packaging parts in a photograph.
///
/// Uses `VNClassifyImageRequest`, Apple's general-purpose image classifier, which ships
/// with the OS. That choice is deliberate: no model file to train, bundle or keep
/// current, no dataset to licence, and it runs entirely on device. The price is that it
/// is a *general* classifier — it recognises a bottle, not a PET bottle — which is why
/// everything it produces is routed through the confirmation step rather than straight
/// to a verdict.
struct PhotoClassifier {
    private static let logger = Logger(subsystem: "app.binmate", category: "PhotoClassifier")

    enum ClassificationError: LocalizedError {
        case unreadableImage
        case nothingRecognised

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "That image could not be read."
            case .nothingRecognised: "Nothing recognisable as packaging in that photo."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .unreadableImage: "Try a different photo."
            case .nothingRecognised: "Get closer to the item, or describe the packaging yourself."
            }
        }
    }

    /// Apple's calibrated filter, which is the documented way to threshold this
    /// classifier. A fixed confidence cut-off does not work here: the taxonomy has over
    /// a thousand classes, so probability mass is spread thin and a *correct* label
    /// routinely scores below 0.05. Measured on a test image, the right answer came back
    /// at 0.017 — any plausible fixed threshold would have discarded it.
    private let recall: Float
    private let precision: Float
    /// How many raw labels to consider when the calibrated filter comes back empty.
    private let fallbackLabelCount: Int

    init(recall: Float = 0.1, precision: Float = 0.5, fallbackLabelCount: Int = 30) {
        self.recall = recall
        self.precision = precision
        self.fallbackLabelCount = fallbackLabelCount
    }

    func suggestions(for image: CGImage) throws -> [PackagingGuess.Suggestion] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("Vision request failed: \(error.localizedDescription, privacy: .public)")
            throw ClassificationError.unreadableImage
        }

        guard let observations = request.results, !observations.isEmpty else {
            throw ClassificationError.nothingRecognised
        }

        // First pass: only labels Vision itself considers reliable at this operating point.
        let calibrated = observations.filter {
            $0.hasMinimumPrecision(precision, forRecall: recall)
        }
        var suggestions = PackagingGuess.suggestions(forLabels: labels(from: calibrated))

        // Second pass: the calibrated filter is strict, and a blurry kitchen photo of a
        // yogurt pot often clears none of it. Falling back to the strongest raw labels
        // is still useful because the user confirms everything anyway — and the UI marks
        // how weak each guess is rather than presenting it as fact.
        if suggestions.isEmpty {
            let strongest = observations
                .sorted { $0.confidence > $1.confidence }
                .prefix(fallbackLabelCount)
            suggestions = PackagingGuess.suggestions(forLabels: labels(from: Array(strongest)))
        }

        guard !suggestions.isEmpty else {
            throw ClassificationError.nothingRecognised
        }
        return suggestions
    }

    private func labels(from observations: [VNClassificationObservation]) -> [(label: String, confidence: Float)] {
        observations.map { (label: $0.identifier, confidence: $0.confidence) }
    }
}
