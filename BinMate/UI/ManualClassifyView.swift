import SwiftUI

/// Builds a product by hand, part by part.
///
/// Most waste has no barcode — loose packaging, takeaway containers, anything bought
/// unpackaged — and Open Food Facts has gaps even where a barcode exists. Without this
/// screen the app would be a dead end exactly when a user most needs an answer, so it is
/// a complete flow rather than a fallback stub.
struct ManualClassifyView: View {
    /// Seeds the editor. Empty when describing something from scratch; pre-filled with
    /// what Open Food Facts returned when the user is correcting a thin or wrong record.
    var initialName: String = ""
    var initialParts: [PackagingComponent] = []
    var onDone: (ScannedProduct) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var parts: [PackagingComponent] = []
    @State private var hasSeeded = false
    @State private var draftShape: TaxonomyID = "en:bottle"
    @State private var draftMaterial: TaxonomyID = "en:pet-1-polyethylene-terephthalate"
    @State private var draftCount = 1

    private var isCorrecting: Bool { !initialParts.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name it, e.g. takeaway coffee cup", text: $name)
                } header: {
                    Text("What is it")
                } footer: {
                    if isCorrecting {
                        Text("Open Food Facts is contributed by volunteers, so a record can be thin or simply wrong. What you see in your hand wins.")
                    }
                }

                Section {
                    Picker("Part", selection: $draftShape) {
                        ForEach(ShapeTaxonomy.pickerShapes, id: \.self) { shape in
                            Label(ShapeTaxonomy.displayName(for: shape), systemImage: ShapeTaxonomy.symbol(for: shape))
                                .tag(shape)
                        }
                    }
                    Picker("Material", selection: $draftMaterial) {
                        ForEach(MaterialTaxonomy.pickerMaterials, id: \.self) { material in
                            Text(MaterialTaxonomy.displayName(for: material)).tag(material)
                        }
                    }
                    Stepper("How many: \(draftCount)", value: $draftCount, in: 1...24)

                    Button {
                        parts.append(PackagingComponent(
                            shape: draftShape,
                            material: draftMaterial,
                            numberOfUnits: draftCount
                        ))
                        draftCount = 1
                    } label: {
                        Label("Add this part", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Add a part")
                } footer: {
                    Text("A yogurt pot is usually three parts: the pot, the foil lid and the cardboard sleeve. Add each one and BinMate sorts them separately.")
                }

                if !parts.isEmpty {
                    Section("Parts added") {
                        ForEach(parts) { part in
                            HStack(spacing: 10) {
                                Image(systemName: part.symbolName)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(part.headline)
                                if part.numberOfUnits > 1 {
                                    Text("× \(part.numberOfUnits)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if let stream = app.engine?.verdict(for: part).stream {
                                    StreamBadge(stream: stream, size: 26)
                                }
                            }
                        }
                        .onDelete { parts.remove(atOffsets: $0) }
                    }
                }
            }
            .navigationTitle(isCorrecting ? "Correct the parts" : "Describe packaging")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Seeds once, so editing then reopening the sheet does not discard work.
                guard !hasSeeded else { return }
                hasSeeded = true
                name = initialName
                parts = initialParts
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sort it") { finish() }
                        .disabled(parts.isEmpty)
                }
            }
        }
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = ScannedProduct(
            barcode: nil,
            name: trimmed.isEmpty ? "Unnamed item" : trimmed,
            brand: nil,
            imageURL: nil,
            components: parts,
            origin: .manual
        )
        dismiss()
        onDone(product)
    }
}
