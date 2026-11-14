import SwiftUI
import SwiftData

/// The result screen: one product, taken apart, with a destination for every piece.
struct VerdictView: View {
    let product: ScannedProduct
    /// Whether arriving at this screen counts as a new scan. False when the screen is
    /// reopened *from* history, which would otherwise duplicate the entry every time.
    var recordToHistory: Bool = true

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    /// The history entry this screen created, kept so a correction updates it in place
    /// rather than leaving the original wrong answer in the log.
    @State private var savedRecord: ScanRecord?
    @State private var didAttemptSave = false
    @State private var correction: ScannedProduct?
    @State private var showingCorrection = false

    /// What is actually on screen: the user's correction if they made one.
    private var activeProduct: ScannedProduct { correction ?? product }

    private var engine: RulesEngine? { app.engine }
    private var verdicts: [BinVerdict] { engine?.verdicts(for: activeProduct) ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let city = app.city {
                    summary(city: city)

                    ForEach(verdicts.groupedByStream, id: \.stream.id) { group in
                        StreamCard(stream: group.stream, verdicts: group.verdicts)
                    }

                    attentionNote
                    thinDataNote

                    CityComparisonStrip(product: activeProduct)

                    sourceFootnote(city: city)
                } else {
                    ContentUnavailableView(
                        "No sorting rules loaded",
                        systemImage: "exclamationmark.triangle",
                        description: Text("BinMate cannot sort anything without a city ruleset. Check Settings for load errors.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Where it goes")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .task { saveToHistoryOnce() }
        // Confirms the lookup landed, and marks each city switch as a deliberate change.
        .sensoryFeedback(.success, trigger: activeProduct.id)
        .sensoryFeedback(.selection, trigger: app.selectedCityID)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCorrection = true
                } label: {
                    Label("Correct the parts", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingCorrection) {
            ManualClassifyView(
                initialName: activeProduct.name,
                initialParts: activeProduct.components
            ) { corrected in
                var updated = corrected
                // Keep the barcode so a correction stays attached to the scanned product.
                updated.barcode = activeProduct.barcode
                apply(correction: updated)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            productThumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(activeProduct.displayTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if let barcode = activeProduct.barcode {
                    Text(barcode)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                TagPill(text: activeProduct.origin.label, symbol: activeProduct.origin.symbol)
            }
            Spacer(minLength: 0)
        }
    }

    private var productThumbnail: some View {
        Group {
            if let url = activeProduct.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
        .frame(width: 64, height: 64)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var placeholderThumbnail: some View {
        Image(systemName: "cube.box")
            .font(.title2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Summary

    private func summary(city: CityRuleset) -> some View {
        let count = verdicts.destinationCount
        let deposit = verdicts.totalDeposit

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text("\(activeProduct.components.count) \(activeProduct.components.count == 1 ? "part" : "parts") → \(count) \(count == 1 ? "destination" : "destinations")")
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 6) {
                RegionBadge(code: city.displayRegionCode, size: 16)
                Text("Rules for \(city.displayName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if deposit > 0 {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "banknote")
                        .foregroundStyle(.green)
                    Text("\(deposit.formattedCurrency(code: verdicts.depositCurrencyCode)) refundable")
                        .font(.subheadline.weight(.semibold))
                    Text("if you return it instead of binning it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var attentionNote: some View {
        let unsure = verdicts.filter { $0.quality == .cityDefault }
        if !unsure.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(unsure.count) \(unsure.count == 1 ? "part has" : "parts have") no specific local rule")
                        .font(.footnote.weight(.semibold))
                    Text("They fall back to the default bin. Worth checking with your local service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Open Food Facts packaging records are contributed by volunteers and are often a
    /// single catch-all entry — a bottle logged only as "plastic", a jar logged as a
    /// bottle. Rather than pretend a one-line record is a full breakdown, say so and
    /// offer the fix, which is the one thing the person holding the object can do better
    /// than any database.
    @ViewBuilder
    private var thinDataNote: some View {
        if activeProduct.origin == .openFoodFacts, activeProduct.components.count <= 1 {
            Button {
                showingCorrection = true
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open Food Facts lists only one part for this product")
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text("Most packaging has more — a cap, a label, a foil seal. Add what you can see and BinMate will sort all of it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func sourceFootnote(city: CityRuleset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rules compiled \(city.compiledOn) from \(city.sourceName).")
            Text("Municipal rules change. Verify anything that matters with your local waste service.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - History

    /// Records the scan once per appearance. History is a log of what the user sorted,
    /// so it keeps the city that was active when the scan happened even if they switch
    /// city afterwards to compare.
    private func saveToHistoryOnce() {
        guard recordToHistory, !didAttemptSave,
              let city = app.city, !activeProduct.components.isEmpty else { return }
        didAttemptSave = true

        let record = ScanRecord(product: activeProduct, city: city)
        context.insert(record)
        try? context.save()
        savedRecord = record
    }

    /// Applies a user correction, updating the history entry in place so the log does not
    /// keep the answer the user has just told us was wrong.
    private func apply(correction corrected: ScannedProduct) {
        correction = corrected
        savedRecord?.update(with: corrected)
        try? context.save()
    }
}

// MARK: - Stream card

/// All the parts of a product that share one destination.
struct StreamCard: View {
    let stream: WasteStream
    let verdicts: [BinVerdict]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                StreamBadge(stream: stream, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.name)
                        .font(.headline)
                    if let localName = stream.localName {
                        Text(localName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                TagPill(text: stream.kindDescription, tint: stream.color)
            }
            .padding()

            Divider().padding(.leading, 16)

            ForEach(verdicts) { verdict in
                PartRow(verdict: verdict)
                if verdict.id != verdicts.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            // A colour stripe so the bin is identifiable at a glance while scrolling.
            Rectangle()
                .fill(stream.color)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.vertical, 8)
                .padding(.leading, 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let parts = verdicts.map(\.component.headline).joined(separator: ", ")
        var text = "\(parts). Goes to \(stream.name)"
        if let localName = stream.localName { text += ", locally called \(localName)" }
        if let instruction = verdicts.compactMap(\.instruction).first { text += ". \(instruction)" }
        return text
    }
}

/// One component and what to do with it.
struct PartRow: View {
    let verdict: BinVerdict
    @State private var showingWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: verdict.component.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(verdict.component.headline)
                    .font(.subheadline.weight(.medium))

                if verdict.component.numberOfUnits > 1 {
                    Text("× \(verdict.component.numberOfUnits)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let deposit = verdict.depositValue, deposit > 0 {
                    Text("+\(deposit.formattedCurrency(code: verdict.stream.depositCurrencyCode))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if let instruction = verdict.instruction {
                Text(instruction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let caution = verdict.caution {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(caution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                TagPill(
                    text: verdict.certainty.label,
                    symbol: verdict.certainty.symbol,
                    tint: verdict.certainty == .high ? .secondary
                        : (verdict.certainty == .low ? .orange : .secondary)
                )
                Button(showingWhy ? "Hide reasoning" : "Why?") {
                    withAnimation(.snappy) { showingWhy.toggle() }
                }
                .font(.caption2.weight(.medium))
            }

            if showingWhy { reasoning }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The engine's working, shown on request.
    ///
    /// An app that says "put this in the yellow bin" and cannot say why is asking to be
    /// trusted on authority. Every step here is checkable against the object in the
    /// user's hand, and names the rule and the source that produced the answer — so
    /// disagreeing with it is possible, which is the point.
    private var reasoning: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Why it is not fully certain, before how it was decided — that is the part
            // a person acts on. Several reasons can apply at once, and collapsing them
            // into one number would throw away exactly what makes them actionable.
            if !verdict.uncertainty.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why not full confidence?")
                        .font(.caption.weight(.semibold))
                    ForEach(verdict.uncertainty, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").font(.caption2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reason.summary).font(.caption)
                                Text(reason.remedy)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.bottom, 2)

                Divider()
            }

            ForEach(verdict.explanation.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 86, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.detail)
                            .font(.caption)
                        if let note = step.note {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if verdict.explanation.ancestry.count > 1 {
                Text(verdict.explanation.ancestry
                        .map { MaterialTaxonomy.displayName(for: $0) }
                        .joined(separator: "  →  "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reasoning: " + verdict.explanation.steps.map { "\($0.label) \($0.detail)" }.joined(separator: ", "))
    }
}

// MARK: - City comparison

/// The same product, resolved against every other city BinMate knows.
///
/// This is the part that makes the point no single-answer sorting app can make: the
/// correct destination is a property of where you are standing, not of the object. It is
/// instant and offline because resolving is a pure function over bundled data.
struct CityComparisonStrip: View {
    let product: ScannedProduct

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The same product elsewhere")
                .font(.subheadline.weight(.semibold))

            Text("Tap a city to re-sort instantly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(app.cities) { city in
                        cityCard(city)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cityCard(_ city: CityRuleset) -> some View {
        let cityVerdicts = RulesEngine(ruleset: city).verdicts(for: product)
        let isSelected = city.id == app.selectedCityID
        let deposit = cityVerdicts.totalDeposit

        return Button {
            withAnimation(.snappy) { app.selectedCityID = city.id }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    RegionBadge(code: city.displayRegionCode, size: 15)
                    Text(city.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    ForEach(cityVerdicts.groupedByStream, id: \.stream.id) { group in
                        Circle()
                            .fill(group.stream.color)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                            .frame(width: 14, height: 14)
                    }
                }

                Text("\(cityVerdicts.destinationCount) \(cityVerdicts.destinationCount == 1 ? "destination" : "destinations")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if deposit > 0 {
                    Text("\(deposit.formattedCurrency(code: cityVerdicts.depositCurrencyCode)) back")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("no deposit")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(width: 148, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(city.displayName): \(cityVerdicts.destinationCount) destinations")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
