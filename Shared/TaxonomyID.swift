import Foundation

/// An identifier borrowed from the Open Food Facts taxonomies, such as
/// `en:pet-polyethylene-terephthalate` for a material or `en:bottle` for a shape.
///
/// Open Food Facts data is user contributed, so the same concept arrives spelled a
/// dozen different ways: `PET`, `en:PET`, `plastic bottle `. Everything is funnelled
/// through `init` so that lookups against the bundled taxonomy and against city rules
/// compare equal regardless of how the value was written upstream.
struct TaxonomyID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let value: String

    init(_ raw: String) {
        self.value = Self.normalize(raw)
    }

    init(stringLiteral literal: StringLiteralType) {
        self.init(literal)
    }

    init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    var description: String { value }

    /// The taxonomy entry without its language prefix, e.g. `bottle` from `en:bottle`.
    var slug: String {
        guard let colon = value.firstIndex(of: ":") else { return value }
        return String(value[value.index(after: colon)...])
    }

    /// A readable fallback for ids that are not in the bundled taxonomy, so an
    /// unrecognised contribution still renders as "Moulded fibre" rather than
    /// `en:moulded-fibre`.
    var humanized: String {
        let words = slug.split(separator: "-").map(String.init)
        guard let first = words.first else { return slug }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }

    /// The language prefix, or `en` when the value never carried one.
    var language: String {
        guard let colon = value.firstIndex(of: ":") else { return "en" }
        return String(value[value.startIndex..<colon])
    }

    /// The entry reduced to a bare comparable term: accents folded away, every run of
    /// punctuation collapsed to a single hyphen.
    ///
    /// Contributed data is not tidy. Open Food Facts stores a term it cannot match as
    /// the contributor typed it, so the same material arrives as `es:Plástico`,
    /// `fr:PP 5 - Polypropylène` or `de:Wickler`. Normalising alone leaves
    /// `fr:pp-5---polypropylène`, which matches nothing. Folding makes all of them
    /// comparable, and it has to agree exactly with `fold()` in
    /// Tools/generate-taxonomy.py, which is what builds the synonym table.
    var folded: String {
        let stripped = slug.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return stripped
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .joined(separator: "-")
    }

    private static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = text.replacingOccurrences(of: "_", with: "-")
        text = text.split(separator: " ").joined(separator: "-")

        // Keep an existing two letter language prefix, otherwise assume English.
        if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) == 2 {
            return text
        }
        return "en:" + text
    }
}
