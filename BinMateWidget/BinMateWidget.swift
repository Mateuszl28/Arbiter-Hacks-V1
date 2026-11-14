import AppIntents
import SwiftUI
import WidgetKit

/// A glanceable reminder of what the local bins are.
///
/// Reads only the bundled rulesets and the selected city from the shared defaults. It
/// never touches the history store: a widget has no business reading a list of what
/// someone throws away, and keeping SwiftData out of it means the widget can never put
/// that store at risk.
///
/// The city comes from the widget's own configuration rather than from the app, because
/// the App Group that would carry the app's choice needs a provisioning profile that an
/// unsigned build does not have — `codesign -d --entitlements` returns an empty dict
/// there. Configuring the widget works in every build, and lets someone who travels keep
/// one widget per city. The app's choice is still used as the starting value when it is
/// readable.
struct BinsEntry: TimelineEntry {
    var date: Date
    var cityName: String
    var regionCode: String
    var streams: [WasteStream]
    /// True when no ruleset could be read at all, so the widget says so rather than
    /// rendering a confident blank.
    var isUnavailable: Bool
}

struct BinsProvider: AppIntentTimelineProvider {
    /// Loaded once per process rather than per timeline request — parsing five JSON
    /// files on every refresh would be wasteful in an extension with a tight budget.
    private static let library = RulesLibrary.loadBundled()

    func placeholder(in context: Context) -> BinsEntry {
        Self.entry(at: Date(), cityID: nil)
    }

    func snapshot(for configuration: SelectCityIntent, in context: Context) async -> BinsEntry {
        Self.entry(at: Date(), cityID: configuration.city?.id)
    }

    func timeline(for configuration: SelectCityIntent, in context: Context) async -> Timeline<BinsEntry> {
        // Nothing to poll for: the rules are bundled and the city changes only when the
        // user says so. A slow heartbeat is enough, and reconfiguring the widget
        // refreshes it immediately.
        let entry = Self.entry(at: Date(), cityID: configuration.city?.id)
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: entry.date) ?? entry.date
        return Timeline(entries: [entry], policy: .after(next))
    }

    static func entry(
        at date: Date,
        cityID: String?,
        library: RulesLibrary = BinsProvider.library
    ) -> BinsEntry {
        // Configured city first; then whatever the app stored, when the App Group is
        // readable; then anything at all, so a widget is never blank.
        let resolved = cityID.flatMap { library.city(id: $0) }
            ?? SharedDefaults.selectedCityID().flatMap { library.city(id: $0) }
            ?? library.fallbackCity

        guard let city = resolved else {
            return BinsEntry(
                date: date,
                cityName: "No city",
                regionCode: "—",
                streams: [],
                isUnavailable: true
            )
        }

        return BinsEntry(
            date: date,
            cityName: city.displayName,
            regionCode: city.displayRegionCode,
            streams: city.kerbsideStreams,
            isUnavailable: false
        )
    }
}

struct BinsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BinsEntry

    private var visibleStreams: [WasteStream] {
        Array(entry.streams.prefix(family == .systemSmall ? 4 : 6))
    }

    var body: some View {
        if entry.isUnavailable {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text("No sorting rules")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
                HStack(spacing: 5) {
                    Text(entry.regionCode)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospaced()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                    Text(entry.cityName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)

                ForEach(visibleStreams) { stream in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(hex: stream.colorHex))
                            .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5) }
                            .frame(width: 11, height: 11)
                        Text(stream.localName ?? stream.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct BinMateWidget: Widget {
    let kind = "BinMateBins"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCityIntent.self, provider: BinsProvider()) { entry in
            BinsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your bins")
        .description("What the bins mean in a city you choose. Tap to scan something.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BinMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        BinMateWidget()
    }
}
