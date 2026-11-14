import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var showingCityPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Your city") {
                    Button {
                        showingCityPicker = true
                    } label: {
                        HStack {
                            if let city = app.city {
                                RegionBadge(code: city.displayRegionCode, size: 18)
                                Text(city.displayName)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("None selected").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let city = app.city {
                        LabeledContent("Rules compiled", value: city.compiledOn)
                        LabeledContent("Source", value: city.sourceName)
                            .lineLimit(3)
                        if let url = city.sourceURL {
                            Link(destination: url) {
                                Label("Open the source", systemImage: "safari")
                            }
                        }
                    }
                }

                Section {
                    Toggle("Offline mode", isOn: Binding(
                        get: { app.offlineOnly },
                        set: { app.offlineOnly = $0 }
                    ))
                } header: {
                    Text("Data")
                } footer: {
                    Text("Offline mode never contacts Open Food Facts. Sample products, your history and all sorting rules keep working — the rules are bundled, not fetched.")
                }

                Section {
                    LabeledContent("Cities loaded", value: "\(app.cities.count)")
                    LabeledContent("Sample products", value: "\(app.samples.products.count)")

                    NavigationLink {
                        DataQualityView()
                    } label: {
                        let report = DataQuality.assess(library: app.library, samples: app.samples)
                        HStack {
                            Label("Data quality", systemImage: "checklist")
                            Spacer(minLength: 0)
                            if report.issues.isEmpty {
                                Text("clean").foregroundStyle(.secondary)
                            } else {
                                Text("\(report.errors.count + report.warnings.count)")
                                    .foregroundStyle(report.errors.isEmpty ? Color.secondary : Color.orange)
                            }
                        }
                    }
                } header: {
                    Text("Bundled data")
                } footer: {
                    Text("These checks already run in the test suite. Surfacing them here means a problem with the data is visible to whoever is holding the phone, not only to whoever runs the scripts.")
                }

                if app.storageIsTemporary {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("History is not being saved")
                                    .font(.subheadline.weight(.semibold))
                                Text("BinMate could not open its on-device history, so scans are being kept in memory and will be lost when the app quits. Sorting itself is unaffected.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if let failure = app.storageFailure {
                                    Text(failure)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !app.loadProblems.isEmpty {
                    Section("Load problems") {
                        ForEach(app.loadProblems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("BinMate breaks a product's packaging into its parts and resolves each part against the collection rules of one city. Rulesets are plain JSON compiled from each city's own published guidance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Rules were compiled by hand from public municipal guidance and are not an official source. Municipal rules change. Verify anything that matters with your local waste service.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Product data from Open Food Facts, used under the Open Database License.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingCityPicker) {
                CityPickerSheet()
            }
        }
    }
}
