import SwiftUI
import SwiftData

@main
struct BinMateApp: App {
    @State private var app = AppModel()

    /// History lives on device only. There is no account and no server, which is also
    /// why there is nothing to breach: a list of what someone throws away is more
    /// revealing than it first appears.
    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: ScanRecord.self)
        } catch {
            // A corrupt store must not brick the app; the rules and scanning still work
            // without history, so fall back to memory and keep going.
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: ScanRecord.self, configurations: configuration)
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(container)
    }
}
