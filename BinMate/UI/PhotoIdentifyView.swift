import SwiftUI
import PhotosUI

/// Identifies packaging from a photo, then hands the result to the user to confirm.
///
/// The screen is built around one idea: the classifier is a starting point, not an
/// answer. Every suggestion arrives unchecked-able but editable, shows what it was
/// derived from, and says plainly when the material was assumed from the shape rather
/// than recognised. A user who disagrees is one tap from fixing it.
struct PhotoIdentifyView: View {
    var onDone: (ScannedProduct) -> Void
    /// Escape hatch when the classifier is no help, which it regularly will not be.
    var onManual: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: Image?
    @State private var suggestions: [PackagingGuess.Suggestion] = []
    @State private var accepted: Set<TaxonomyID> = []
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label(
                            image == nil ? "Choose a photo" : "Choose a different photo",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }

                    if let image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text("Runs entirely on this device. The photo is never uploaded and is not kept.")
                }

                if isWorking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking at the photo…").foregroundStyle(.secondary)
                        }
                    }
                }

                if let failure {
                    Section {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Describe the packaging myself") {
                            dismiss()
                            onManual()
                        }
                        .font(.footnote.weight(.medium))
                    }
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.shape) { suggestion in
                            suggestionRow(suggestion)
                        }
                    } header: {
                        Text("What it looks like")
                    } footer: {
                        Text("These are guesses from a general image classifier — it recognises a bottle, not what the bottle is made of. Pick the parts that are really there; you can edit them on the next screen.")
                    }
                }
            }
            .navigationTitle("Identify from a photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        finish(with: suggestions.filter { accepted.contains($0.shape) })
                    }
                    .disabled(accepted.isEmpty)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await classify(newItem) }
            }
        }
    }

    private func suggestionRow(_ suggestion: PackagingGuess.Suggestion) -> some View {
        Button {
            if accepted.contains(suggestion.shape) {
                accepted.remove(suggestion.shape)
            } else {
                accepted.insert(suggestion.shape)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: accepted.contains(suggestion.shape) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(accepted.contains(suggestion.shape) ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ShapeTaxonomy.displayName(for: suggestion.shape)) · \(MaterialTaxonomy.displayName(for: suggestion.material))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        TagPill(
                            text: suggestion.strength.label,
                            tint: suggestion.strength == .likely ? .green : .secondary
                        )
                        if suggestion.materialIsAssumed {
                            TagPill(text: "material assumed", symbol: "questionmark.circle", tint: .orange)
                        }
                    }

                    Text("recognised as “\(suggestion.sourceLabel.replacingOccurrences(of: "_", with: " "))”")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func classify(_ item: PhotosPickerItem) async {
        isWorking = true
        failure = nil
        suggestions = []
        accepted = []
        defer { isWorking = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            failure = "That image could not be read. Try a different photo."
            return
        }

        image = Image(uiImage: uiImage)

        do {
            let found = try PhotoClassifier().suggestions(for: cgImage)
            suggestions = found
            // Pre-select the strongest guess only. Ticking everything by default would
            // quietly put the classifier's mistakes into the user's verdict.
            if let best = found.first { accepted = [best.shape] }
        } catch let error as PhotoClassifier.ClassificationError {
            failure = [error.errorDescription, error.recoverySuggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        } catch {
            failure = "Could not analyse that photo."
        }
    }

    private func finish(with chosen: [PackagingGuess.Suggestion]) {
        let product = ScannedProduct(
            barcode: nil,
            name: "Photographed item",
            brand: nil,
            imageURL: nil,
            components: chosen.map(PackagingGuess.component(from:)),
            origin: .manual
        )
        dismiss()
        onDone(product)
    }
}
