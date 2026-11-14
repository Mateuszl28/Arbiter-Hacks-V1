import SwiftUI
import SwiftData

/// Home screen. One obvious action, and an honest route forward when it fails.
struct ScanView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context

    @State private var showingScanner = false
    @State private var showingManualBarcode = false
    @State private var showingManualPacking = false
    @State private var showingPhotoIdentify = false
    @State private var showingCityPicker = false
    @State private var typedBarcode = ""

    @State private var isLooking = false
    @State private var lookupError: ProductLookupError?
    @State private var resolved: ScannedProduct?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    cityChip
                    scanButton
                    if isLooking { lookingUp }
                    if let lookupError { errorCard(lookupError) }
                    noBarcodeOptions
                    sampleProducts
                }
                .padding()
            }
            .navigationTitle("BinMate")
            .background(Color(.systemGroupedBackground))
            .navigationDestination(item: $resolved) { product in
                VerdictView(product: product)
            }
            .sheet(isPresented: $showingScanner) {
                ScannerSheet(
                    onBarcode: { look(up: $0) },
                    onManual: { showingManualPacking = true }
                )
            }
            .sheet(isPresented: $showingCityPicker) {
                CityPickerSheet()
            }
            .sheet(isPresented: $showingManualPacking) {
                ManualClassifyView { product in
                    resolved = product
                }
            }
            .sheet(isPresented: $showingPhotoIdentify) {
                PhotoIdentifyView(
                    onDone: { resolved = $0 },
                    onManual: { showingManualPacking = true }
                )
            }
            // Opened from the widget or a Shortcut. Guarded on the count rather than a
            // flag so a second request while the app is already open still opens it.
            .onChange(of: app.scanRequests) { _, _ in
                lookupError = nil
                resolved = nil
                showingScanner = true
            }
            .alert("Enter a barcode", isPresented: $showingManualBarcode) {
                TextField("Barcode digits", text: $typedBarcode)
                    .keyboardType(.numberPad)
                Button("Look it up") {
                    let trimmed = typedBarcode.trimmingCharacters(in: .whitespaces)
                    typedBarcode = ""
                    guard !trimmed.isEmpty else { return }
                    look(up: trimmed)
                }
                Button("Cancel", role: .cancel) { typedBarcode = "" }
            }
        }
    }

    // MARK: - Pieces

    private var cityChip: some View {
        Button {
            showingCityPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                if let city = app.city {
                    RegionBadge(code: city.displayRegionCode, size: 18)
                    Text("Sorting by \(city.displayName) rules")
                        .font(.subheadline.weight(.medium))
                } else {
                    Text("No city selected").font(.subheadline.weight(.medium))
                }
                Image(systemName: "chevron.right").font(.caption2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Change the city whose rules BinMate uses")
    }

    private var scanButton: some View {
        Button {
            lookupError = nil
            showingScanner = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 54, weight: .light))
                Text("Scan a barcode")
                    .font(.title3.weight(.semibold))
                Text("BinMate takes the packaging apart and tells you where each piece goes")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var lookingUp: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Looking up the packaging…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(_ error: ProductLookupError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(error.errorDescription ?? "Lookup failed")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Describe the packaging myself") {
                lookupError = nil
                showingManualPacking = true
            }
            .font(.footnote.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var sampleProducts: some View {
        if !app.samples.products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Try it without a camera")
                    .font(.subheadline.weight(.semibold))
                Text("Real packaging breakdowns, bundled with the app. No network needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(app.samples.products) { sample in
                    Button {
                        lookupError = nil
                        resolved = sample
                    } label: {
                        sampleRow(sample)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sampleRow(_ sample: ScannedProduct) -> some View {
        let sampleVerdicts = app.engine?.verdicts(for: sample) ?? []

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sample.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text("\(sample.components.count) parts → \(sampleVerdicts.destinationCount) destinations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(sampleVerdicts.groupedByStream, id: \.stream.id) { group in
                    Circle()
                        .fill(group.stream.color)
                        .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                        .frame(width: 12, height: 12)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var noBarcodeOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No barcode?")
                .font(.subheadline.weight(.semibold))

            Button {
                lookupError = nil
                showingPhotoIdentify = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Identify from a photo")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Suggests the parts, on device. You confirm them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                showingManualPacking = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Describe the packaging")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Add each part yourself — always works.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button("Type a barcode instead") { showingManualBarcode = true }
                .font(.footnote.weight(.medium))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Lookup

    private func look(up barcode: String) {
        lookupError = nil
        isLooking = true

        Task {
            let resolver = ProductResolver(
                client: app.client,
                samples: app.samples,
                context: context,
                offlineOnly: app.offlineOnly
            )
            do {
                let product = try await resolver.resolve(barcode: barcode)
                isLooking = false
                resolved = product
            } catch let error as ProductLookupError {
                isLooking = false
                lookupError = error
            } catch {
                isLooking = false
                lookupError = .malformedResponse
            }
        }
    }
}
