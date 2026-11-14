import SwiftUI

/// A single screen that states the premise and takes the one input that matters.
///
/// Deliberately not a carousel. The app's idea takes one sentence to explain, and the
/// only thing it needs before it can work is which city the user is in.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var locator: CityLocator?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.tint)

                    Text("One product is not one piece of waste")
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A yogurt pot is a plastic pot, a foil lid and a cardboard sleeve. In most cities those three go to three different places.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    point(
                        symbol: "barcode.viewfinder",
                        title: "Scan the barcode",
                        detail: "BinMate looks up what the packaging is actually made of."
                    )
                    point(
                        symbol: "mappin.and.ellipse",
                        title: "Answers for where you are",
                        detail: "A PET bottle goes in the yellow bin in Kraków, but back to the shop for 25 cents in Berlin. Same bottle, different answer."
                    )
                    point(
                        symbol: "wifi.slash",
                        title: "Works offline",
                        detail: "Every sorting rule ships with the app. Nothing to wait for."
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Where are you?")
                        .font(.headline)

                    // Offered here rather than only in Settings: this is the one moment
                    // the city must be chosen, and the one moment someone has no basis
                    // for choosing beyond where they happen to be standing.
                    locationRow

                    ForEach(app.cities) { city in
                        Button {
                            app.selectedCityID = city.id
                        } label: {
                            CityRow(city: city, isSelected: city.id == app.selectedCityID)
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            city.id == app.selectedCityID ? Color.accentColor : .clear,
                                            lineWidth: 2
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    app.hasCompletedOnboarding = true
                } label: {
                    Text("Start sorting")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.city == nil)

                Text("Rules were compiled from public municipal guidance and are not an official source. Verify anything that matters with your local waste service.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                locator?.locate { cityID in
                    app.selectedCityID = cityID
                }
            } label: {
                HStack(spacing: 8) {
                    if locator?.isBusy == true {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location")
                    }
                    Text(locator?.isBusy == true ? "Checking…" : "Use my location")
                        .font(.subheadline.weight(.medium))
                }
            }
            .disabled(locator?.isBusy == true)

            switch locator?.state {
            case .denied:
                Text("Location is off, so pick a city below — it works just as well.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .located(let cityID, let summary, let trustworthy):
                Label {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(trustworthy ? .secondary : .primary)
                } icon: {
                    Image(systemName: trustworthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trustworthy ? Color.green : .orange)
                }
                if !trustworthy, cityID != app.selectedCityID,
                   let city = app.library.city(id: cityID) {
                    Button("Use \(city.displayName) anyway") {
                        app.selectedCityID = cityID
                    }
                    .font(.footnote.weight(.medium))
                }
            default:
                EmptyView()
            }
        }
        .task {
            if locator == nil { locator = CityLocator(library: app.library) }
        }
    }

    private func point(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
