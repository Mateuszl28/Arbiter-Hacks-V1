import SwiftUI
import WidgetKit

/// A glanceable reminder of what the local bins are.
///
/// Reads only the bundled rulesets and the selected city from the shared defaults. It
/// never touches the history store: a widget has no business reading a list of what
/// someone throws away, and keeping SwiftData out of it means the widget can never put
/// that store at risk.
///
/// One caveat worth knowing before trusting a screenshot: reading the app's choice needs
/// the `group.app.binmate` App Group, and App Group entitlements require a provisioning
/// profile. An unsigned or ad-hoc simulator build therefore gets *no* entitlements —
/// verified with `codesign -d --entitlements`, which returns an empty dict — so the
/// widget falls back to the first bundled city instead of following the app. On a signed
/// build it tracks the app's selection. The fallback is a real city with real rules, so
/// the widget is never wrong, only potentially about the wrong place.
struct BinsEntry: TimelineEntry {
    var date: Date
    var cityName: String
    var regionCode: String
    var streams: [WasteStream]
    /// True when no ruleset could be read at all, so the widget says so rather than
    /// rendering a confident blank.
    var isUnavailable: Bool
}

struct BinsProvider: TimelineProvider {
    /// Loaded once per process rather than per timeline request — parsing five JSON
    /// files on every refresh would be wasteful in an extension with a tight budget.
    private static let library = RulesLibrary.loadBundled()

    func placeholder(in context: Context) -> BinsEntry {
        Self.entry(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BinsEntry) -> Void) {
        completion(Self.entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BinsEntry>) -> Void) {
        // The rules are bundled and the city changes only when the user says so, so there
        // is nothing to poll for. Refresh on a slow heartbeat and rely on the app
        // reloading timelines when the city actually changes.
        let entry = Self.entry(at: Date())
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static func entry(at date: Date, library: RulesLibrary = BinsProvider.library) -> BinsEntry {
        let stored = SharedDefaults.selectedCityID() ?? ""
        guard let city = library.city(id: stored) ?? library.fallbackCity else {
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
        StaticConfiguration(kind: kind, provider: BinsProvider()) { entry in
            BinsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Your bins")
        .description("What the bins mean where you are. Tap to scan something.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BinMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        BinMateWidget()
    }
}
