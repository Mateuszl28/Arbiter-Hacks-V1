import AppIntents
import SwiftUI

/// Siri's view of `QuickItem`.
///
/// Kept as a thin mirror of the plain enum so the mapping that matters stays testable
/// without a device.
enum QuickItemAppEnum: String, AppEnum {
    case plasticBottle, glassBottle, drinksCan, glassJar, yogurtPot, cardboardBox
    case plasticBag, beverageCarton, compostableCup, bottleCap, paperLabel, foilWrapper

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Item" }

    // Must be a literal: the App Intents metadata processor reads this at build time and
    // rejects anything computed, so it cannot be derived from `QuickItem.displayName`.
    // `verify-intents.sh` asserts the two stay in step.
    static var caseDisplayRepresentations: [QuickItemAppEnum: DisplayRepresentation] = [
        .plasticBottle: "plastic bottle",
        .glassBottle: "glass bottle",
        .drinksCan: "drinks can",
        .glassJar: "glass jar",
        .yogurtPot: "yogurt pot",
        .cardboardBox: "cardboard box",
        .plasticBag: "plastic bag",
        .beverageCarton: "drinks carton",
        .compostableCup: "compostable cup",
        .bottleCap: "bottle cap",
        .paperLabel: "paper label",
        .foilWrapper: "foil wrapper",
    ]

    var quickItem: QuickItem {
        QuickItem(rawValue: rawValue) ?? .plasticBottle
    }
}

/// "Hey Siri, which bin for a yogurt pot?"
///
/// Answers without opening the app, because the rules are bundled and resolving them is
/// a pure function — there is nothing to fetch and nothing to wait for.
struct WhichBinIntent: AppIntent {
    static var title: LocalizedStringResource = "Which Bin"

    static var description = IntentDescription(
        "Says where an everyday item goes under your city's collection rules.",
        categoryName: "Sorting",
        searchKeywords: ["bin", "recycle", "waste", "sort", "rubbish", "trash"]
    )

    /// Answering is read-only and instant, so there is no reason to interrupt the user
    /// by bringing the app forward.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item")
    var item: QuickItemAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Which bin for a \(\.$item)")
    }

    /// Main actor because the snippet is a SwiftUI view. The lookup itself is pure and
    /// synchronous, so this costs nothing.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let lookup = BinLookup()

        guard let answer = lookup.answer(for: item.quickItem) else {
            return .result(
                dialog: "BinMate has no city rules loaded, so it cannot answer that yet.",
                view: EmptyAnswerSnippet()
            )
        }

        return .result(
            dialog: IntentDialog(stringLiteral: answer.spoken),
            view: BinAnswerSnippet(answer: answer)
        )
    }
}

/// Opens the app's scanner straight from Siri or a Shortcut.
struct ScanPackagingIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Packaging"

    static var description = IntentDescription(
        "Opens BinMate ready to scan a barcode.",
        categoryName: "Sorting"
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // This runs in the app's own process, so standard defaults are the app's own and
        // the request is waiting by the time the app becomes active.
        PendingAction.requestScanner()
        return .result()
    }
}

struct BinMateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhichBinIntent(),
            phrases: [
                "Which bin in \(.applicationName)",
                "Ask \(.applicationName) which bin",
                "Where does this go in \(.applicationName)",
            ],
            shortTitle: "Which Bin",
            systemImageName: "arrow.triangle.branch"
        )
        AppShortcut(
            intent: ScanPackagingIntent(),
            phrases: [
                "Scan packaging with \(.applicationName)",
                "Open \(.applicationName) scanner",
            ],
            shortTitle: "Scan Packaging",
            systemImageName: "barcode.viewfinder"
        )
    }
}

// MARK: - Snippets

/// Shown beside Siri's spoken answer. Repeats the bin visually because a colour is
/// easier to act on at an actual bin than a name is.
struct BinAnswerSnippet: View {
    let answer: BinLookup.Answer

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StreamBadge(stream: answer.verdict.stream, size: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(answer.verdict.stream.name)
                    .font(.headline)
                if let localName = answer.verdict.stream.localName {
                    Text(localName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(answer.item.displayName) · \(answer.city.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let deposit = answer.verdict.depositValue, deposit > 0 {
                    Text("\(deposit.formattedCurrency(code: answer.verdict.stream.depositCurrencyCode)) back")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

struct EmptyAnswerSnippet: View {
    var body: some View {
        Label("No city rules loaded", systemImage: "exclamationmark.triangle")
            .padding()
    }
}
