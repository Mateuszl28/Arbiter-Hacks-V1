import SwiftUI

/// The city's rule book, browsable and searchable.
struct CityGuideView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    private var guide: CityGuide? {
        app.city.map(CityGuide.init(ruleset:))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let guide {
                    List {
                        if !query.isEmpty {
                            searchResults(guide)
                        } else {
                            streamSections(guide)
                            provenance(guide.ruleset)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No sorting rules loaded",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Check Settings for load errors.")
                    )
                }
            }
            .navigationTitle("Bins")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Yogurt pot, PET, foil…"
            )
        }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchResults(_ guide: CityGuide) -> some View {
        let results = guide.search(query)

        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Section {
                ForEach(results) { result in
                    HStack(spacing: 12) {
                        StreamBadge(stream: result.verdict.stream, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.label)
                                .font(.subheadline.weight(.medium))
                            Text(result.verdict.stream.localName ?? result.verdict.stream.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let deposit = result.verdict.depositValue, deposit > 0 {
                            Text("+\(deposit.formattedCurrency(code: result.verdict.stream.depositCurrencyCode))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("In \(guide.ruleset.displayName)")
            } footer: {
                Text("Answers come from the same rules the scanner uses, so they cannot disagree with it.")
            }
        }
    }

    // MARK: - Browse

    @ViewBuilder
    private func streamSections(_ guide: CityGuide) -> some View {
        ForEach(guide.orderedStreams) { stream in
            Section {
                let entries = guide.entries(forStream: stream.id)

                if entries.isEmpty {
                    Text(guide.isDefaultStream(stream)
                         ? "Anything with no rule of its own ends up here."
                         : "No rules point here yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry)
                    }
                    if guide.isDefaultStream(stream) {
                        Text("…and anything else with no rule of its own.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 10) {
                    StreamBadge(stream: stream, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stream.name)
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                        if let localName = stream.localName {
                            Text(localName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                    Spacer(minLength: 0)
                    if let deposit = stream.depositAmount, deposit > 0 {
                        Text("\(deposit.formattedCurrency(code: stream.depositCurrencyCode)) back")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .textCase(nil)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func provenance(_ ruleset: CityRuleset) -> some View {
        Section {
            let conflicts = RuleConflicts.findings(in: ruleset)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(ruleset.rules.count) rules across \(ruleset.streams.count) collection streams.")
                // Rules are data, and data can contradict itself. A rule shadowed by a
                // broader one above it never fires, and nothing else would say so.
                if conflicts.isEmpty {
                    Label("No rule here is unreachable or contradicted by another.", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(conflicts, id: \.self) { finding in
                        Label(
                            "Rule \(finding.ruleIndex + 1) \(finding.message)",
                            systemImage: finding.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle"
                        )
                        .foregroundStyle(finding.severity == .error ? Color.orange : .secondary)
                    }
                }
                Text("Compiled \(ruleset.compiledOn) from \(ruleset.sourceName). Not an official source — verify anything that matters with your local waste service.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let url = ruleset.sourceURL {
                Link(destination: url) {
                    Label("Open the source", systemImage: "safari")
                        .font(.footnote)
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: CityGuide.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.materials)
                    .font(.subheadline.weight(.medium))
                if let shapeNote = entry.shapeNote {
                    TagPill(text: shapeNote)
                }
            }

            if let instruction = entry.instruction {
                Text(instruction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let caution = entry.caution {
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
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
