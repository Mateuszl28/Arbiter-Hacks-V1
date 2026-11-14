import SwiftUI

/// Hands the rules back out.
///
/// The claim running through this app is that cities are data. That is only worth
/// something if the data can leave — otherwise it is a database with an app wrapped
/// around it. Exporting costs nothing here, because the rules were never anything but
/// files.
struct ExportRulesView: View {
    @Environment(AppModel.self) private var app
    @State private var format = RulesetExport.Format.markdown
    @State private var exported: ExportedFile?

    var body: some View {
        List {
            Section {
                Picker("Format", selection: $format) {
                    ForEach(RulesetExport.Format.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Format")
            } footer: {
                Text("\(app.cities.count) cities, \(app.cities.reduce(0) { $0 + $1.rules.count }) rules. Every export cites the source each ruleset was compiled from and the date it was compiled.")
            }

            Section {
                if let exported {
                    ShareLink(item: exported, preview: SharePreview(exported.name)) {
                        Label("Share \(exported.name)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        prepare()
                    } label: {
                        Label("Prepare export", systemImage: "doc.badge.arrow.up")
                    }
                }
            } footer: {
                Text("Exports carry the same caveat the app does: these rules were compiled by hand from public municipal guidance and are not an official source. A rule lifted out of here without that sentence is a worse artefact than no export at all.")
            }

            if let exported {
                Section("Preview") {
                    Text(exported.preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(14)
                }
            }
        }
        .navigationTitle("Export rules")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: format) { _, _ in exported = nil }
    }

    private func prepare() {
        let text = RulesetExport.export(app.cities, as: format)
        let name = RulesetExport.filename(
            for: format,
            compiledOn: app.cities.map(\.compiledOn).max() ?? "export"
        )
        let url = URL.temporaryDirectory.appending(path: name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exported = ExportedFile(
            url: url,
            name: name,
            preview: String(text.prefix(900))
        )
    }
}

/// A file ready to hand to the share sheet.
private struct ExportedFile: Transferable {
    var url: URL
    var name: String
    var preview: String

    static var transferRepresentation: some TransferRepresentation {
        // Exported as a plain file so the receiving app gets the real artefact rather
        // than a string pasted into a message.
        ProxyRepresentation(exporting: \.url)
    }
}
