import SwiftUI

/// Choosing which city's rules apply.
///
/// Presented as a first-class decision rather than buried in settings, because it is the
/// single input that changes every answer the app gives.
struct CityPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var locator: CityLocator?

    var body: some View {
        NavigationStack {
            List {
                detectSection

                Section {
                    ForEach(app.cities) { city in
                        Button {
                            app.selectedCityID = city.id
                            dismiss()
                        } label: {
                            CityRow(city: city, isSelected: city.id == app.selectedCityID)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Each city is a JSON ruleset bundled with the app, compiled from that city's own published guidance. Adding a city needs no code change.")
                }

                if !app.loadProblems.isEmpty {
                    Section("Could not be loaded") {
                        ForEach(app.loadProblems, id: \.self) { problem in
                            Text(problem)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task {
                if locator == nil { locator = CityLocator(library: app.library) }
            }
            .navigationTitle("Your city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension CityPickerSheet {
    @ViewBuilder
    var detectSection: some View {
        Section {
            Button {
                locator?.locate { cityID in
                    app.selectedCityID = cityID
                }
            } label: {
                HStack(spacing: 10) {
                    if locator?.isBusy == true {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location")
                    }
                    Text(locator?.isBusy == true ? "Checking…" : "Use my location")
                    Spacer(minLength: 0)
                }
            }
            .disabled(locator?.isBusy == true)

            switch locator?.state {
            case .denied:
                Text("Location access is off. You can pick a city by hand below, which works just as well.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .located(let cityID, let summary, let trustworthy):
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(trustworthy ? .secondary : .primary)
                    } icon: {
                        Image(systemName: trustworthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(trustworthy ? Color.green : .orange)
                    }

                    // A distant match is offered, never applied silently.
                    if !trustworthy, cityID != app.selectedCityID,
                       let city = app.library.city(id: cityID) {
                        Button("Use \(city.displayName) anyway") {
                            app.selectedCityID = cityID
                        }
                        .font(.footnote.weight(.medium))
                    }
                }
            default:
                EmptyView()
            }
        } footer: {
            Text("Your coordinates stay on the device — they are only measured against the handful of cities bundled with the app.")
        }
    }
}

struct CityRow: View {
    let city: CityRuleset
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RegionBadge(code: city.displayRegionCode, size: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(city.displayName)
                    .font(.headline)
                Text(city.region)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(city.streams) { stream in
                        Circle()
                            .fill(stream.color)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)

                Text("\(city.streams.count) collection streams · \(city.rules.count) rules · compiled \(city.compiledOn)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
