import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = Tabs.scan

    private enum Tabs: Hashable {
        case scan, bins, history, sorting, settings
    }

    var body: some View {
        if app.hasCompletedOnboarding {
            TabView(selection: $selectedTab) {
                Tab("Scan", systemImage: "barcode.viewfinder", value: Tabs.scan) {
                    ScanView()
                }
                Tab("Bins", systemImage: "list.bullet.rectangle", value: Tabs.bins) {
                    CityGuideView()
                }
                Tab("History", systemImage: "clock.arrow.circlepath", value: Tabs.history) {
                    HistoryView()
                }
                Tab("Sorting", systemImage: "chart.bar", value: Tabs.sorting) {
                    StatsView()
                }
                Tab("Settings", systemImage: "gearshape", value: Tabs.settings) {
                    SettingsView()
                }
            }
            // A request for the scanner has to land on the Scan tab first, or the sheet
            // would open over whatever the user happened to be looking at.
            .onOpenURL { url in
                guard DeepLink.isScanRequest(url) else { return }
                selectedTab = .scan
                app.requestScanner()
            }
            .onChange(of: app.scanRequests) { _, _ in
                selectedTab = .scan
            }
            .onChange(of: scenePhase) { _, phase in
                // Picks up a request left by the Shortcuts action, which ran before the
                // app was on screen.
                if phase == .active { app.consumePendingScannerRequest() }
            }
            .task { app.consumePendingScannerRequest() }
        } else {
            OnboardingView()
        }
    }
}
