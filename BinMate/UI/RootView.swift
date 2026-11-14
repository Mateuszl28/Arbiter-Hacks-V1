import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.hasCompletedOnboarding {
            TabView {
                Tab("Scan", systemImage: "barcode.viewfinder") {
                    ScanView()
                }
                Tab("Bins", systemImage: "list.bullet.rectangle") {
                    CityGuideView()
                }
                Tab("History", systemImage: "clock.arrow.circlepath") {
                    HistoryView()
                }
                Tab("Sorting", systemImage: "chart.bar") {
                    StatsView()
                }
                Tab("Settings", systemImage: "gearshape") {
                    SettingsView()
                }
            }
        } else {
            OnboardingView()
        }
    }
}
