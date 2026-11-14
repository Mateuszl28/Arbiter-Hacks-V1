import Foundation

/// Hands the rulesets back out in formats somebody else can use.
///
/// The claim running through this project is that cities are *data*. A claim like that is
/// only worth something if the data can leave — otherwise it is a database with an app
/// wrapped around it, which is the same lock-in dressed differently. Exporting costs
/// nothing here because the rules were never anything but files.
///
/// Every export carries its provenance and its caveat. A rule lifted out of this app and
/// dropped into someone else's without the words "compiled by hand from public guidance,
/// not an official source" would be a worse artefact than no export at all.
enum RulesetExport {
    enum Format: String, CaseIterable, Sendable {
        case csv
        case markdown
        case json

        var fileExtension: String {
            switch self {
            case .csv: "csv"
            case .markdown: "md"
            case .json: "json"
            }
        }

        var displayName: String {
            switch self {
            case .csv: "CSV — one row per rule"
            case .markdown: "Markdown — readable rule book"
            case .json: "JSON — the rulesets as they ship"
            }
        }
    }

    static func export(_ cities: [CityRuleset], as format: Format) -> String {
        switch format {
        case .csv: csv(cities)
        case .markdown: markdown(cities)
        case .json: json(cities)
        }
    }

    static func filename(for format: Format, compiledOn: String) -> String {
        "binmate-rules-\(compiledOn).\(format.fileExtension)"
    }

    // MARK: - CSV

    /// One row per rule.
    ///
    /// The quoting is the whole job. Instructions contain commas ("Rinse it, cut it open,
    /// dry it flat") and quotation marks, and a naive join would silently shift every
    /// column after the first instruction — producing a file that opens fine and means
    /// something else.
    static func csv(_ cities: [CityRuleset]) -> String {
        var lines = [
            [
                "city_id", "city", "region", "compiled_on", "source",
                "rule_index", "materials", "shapes", "stream_id", "stream",
                "stream_kind", "local_name", "deposit", "currency",
                "instruction", "caution",
            ].joined(separator: ",")
        ]

        for city in cities {
            for (index, rule) in city.rules.enumerated() {
                let stream = city.stream(id: rule.stream)
                let materials: String = rule.materials.map(\.value).joined(separator: " ")
                let shapes: String = (rule.shapes ?? []).map(\.value).joined(separator: " ")
                let kind: String = stream.map { String(describing: $0.kind) } ?? ""
                let deposit: String = stream?.depositAmount.map { "\($0)" } ?? ""

                var fields: [String] = []
                fields.append(city.id)
                fields.append(city.displayName)
                fields.append(city.region)
                fields.append(city.compiledOn)
                fields.append(city.sourceName)
                fields.append(String(index + 1))
                fields.append(materials)
                fields.append(shapes)
                fields.append(rule.stream)
                fields.append(stream?.name ?? "")
                fields.append(kind)
                fields.append(stream?.localName ?? "")
                fields.append(deposit)
                fields.append(stream?.depositCurrencyCode ?? "")
                fields.append(rule.instruction ?? "")
                fields.append(rule.caution ?? "")

                lines.append(fields.map(quoted).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 quoting: wrap when the value contains a comma, quote or newline, and
    /// double any quote inside.
    private static func quoted(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Markdown

    static func markdown(_ cities: [CityRuleset]) -> String {
        var out = """
        # BinMate sorting rules

        Collection rules for \(cities.count) \(cities.count == 1 ? "city" : "cities"), as \
        bundled with the app.

        **These were compiled by hand from each city's published public guidance and are \
        not an official source.** Municipal rules change. Verify anything that matters \
        with the local waste service. Each city below cites where its rules came from and \
        when they were compiled.

        """

        for city in cities.sorted(by: { $0.displayName < $1.displayName }) {
            out += "\n## \(city.displayName) — \(city.region)\n\n"
            out += "Compiled \(city.compiledOn) from \(city.sourceName)."
            if let url = city.sourceURL { out += " \(url.absoluteString)" }
            out += "\n\n### Collection streams\n\n"

            for stream in city.streams {
                var line = "- **\(stream.name)**"
                if let localName = stream.localName { line += " (\(localName))" }
                line += " — \(String(describing: stream.kind))"
                if let deposit = stream.depositAmount, let currency = stream.depositCurrencyCode {
                    line += ", \(deposit) \(currency) deposit"
                }
                out += line + "\n"
            }

            out += "\n### Rules\n\nApplied in order; the first match wins, and the material "
            out += "hierarchy is walked from the most specific upwards.\n\n"

            for (index, rule) in city.rules.enumerated() {
                let materials = rule.materials
                    .map { MaterialTaxonomy.displayName(for: $0) }
                    .joined(separator: ", ")
                out += "\(index + 1). **\(materials)**"
                if let shapes = rule.shapes, !shapes.isEmpty {
                    out += " _(\(shapes.map { ShapeTaxonomy.displayName(for: $0).lowercased() }.joined(separator: ", ")) only)_"
                }
                out += " → \(city.stream(id: rule.stream)?.name ?? rule.stream)\n"
                if let instruction = rule.instruction { out += "   - \(instruction)\n" }
                if let caution = rule.caution { out += "   - ⚠︎ \(caution)\n" }
            }

            let defaultName = city.defaultStream?.name ?? city.defaultStreamID
            out += "\nAnything unmatched goes to **\(defaultName)**.\n"
        }

        return out
    }

    // MARK: - JSON

    static func json(_ cities: [CityRuleset]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(cities),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}
