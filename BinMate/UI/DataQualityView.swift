import SwiftUI

/// What the app knows about the state of its own data.
///
/// These checks already existed and were scattered: load failures here, conflicts at the
/// foot of a rule book, coverage inside a city page, staleness inside a verdict. Each was
/// visible only to someone already looking at that screen. Together they answer a question
/// none of them could — is this data in good shape, and if not, what is worst?
struct DataQualityView: View {
    @Environment(AppModel.self) private var app

    private var report: DataQuality {
        DataQuality.assess(library: app.library, samples: app.samples)
    }

    var body: some View {
        let report = report

        List {
            Section {
                // What was examined, not only what was wrong. A clean report means
                // nothing unless you know its scope.
                LabeledContent("Cities", value: "\(report.checked.cities)")
                LabeledContent("Rules", value: "\(report.checked.rules)")
                LabeledContent("Common materials", value: "\(report.checked.materials)")
                LabeledContent("Sample products", value: "\(report.checked.products)")
            } header: {
                Text("Checked")
            } footer: {
                if report.issues.isEmpty {
                    Text("Nothing to report. Every ruleset loaded, no rule is unreachable, no source is overdue, and no bundled product looks malformed.")
                } else {
                    Text("\(report.errors.count) problem\(report.errors.count == 1 ? "" : "s") and \(report.warnings.count) thing\(report.warnings.count == 1 ? "" : "s") worth a look.")
                }
            }

            ForEach(grouped(report.issues), id: \.area) { group in
                Section(group.area) {
                    ForEach(group.issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }

            Section {
                Text("There is deliberately no overall score. A single number would have to weigh a dead rule against an ageing source against a thin product record, and that weighting would be invented.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Data quality")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func grouped(_ issues: [DataQuality.Issue]) -> [(area: String, issues: [DataQuality.Issue])] {
        var order: [String] = []
        var buckets: [String: [DataQuality.Issue]] = [:]
        for issue in issues {
            if buckets[issue.area] == nil { order.append(issue.area) }
            buckets[issue.area, default: []].append(issue)
        }
        return order.map { (area: $0, issues: buckets[$0] ?? []) }
    }
}

private struct IssueRow: View {
    let issue: DataQuality.Issue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.footnote)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(issue.detail)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                // Every issue carries what would resolve it. A list of complaints with
                // nothing to do about them is a list nobody opens twice.
                Text(issue.action)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch issue.severity {
        case .error: "exclamationmark.triangle.fill"
        case .warning: "exclamationmark.circle"
        case .info: "info.circle"
        }
    }

    private var tint: Color {
        switch issue.severity {
        case .error: .orange
        case .warning: .secondary
        case .info: .secondary
        }
    }
}
