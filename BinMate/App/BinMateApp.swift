import SwiftUI
import SwiftData

@main
struct BinMateApp: App {
    @State private var app = AppModel()

    /// History lives on device only. There is no account and no server, which is also
    /// why there is nothing to breach: a list of what someone throws away is more
    /// revealing than it first appears.
    private let store: Store = {
        do {
            return Store(container: try ModelContainer(for: ScanRecord.self), isTemporary: false, failure: nil)
        } catch {
            // A store that will not open must not brick the app — the rules, the scanner
            // and the rule book all work without history. But falling back silently is
            // worse than the crash it avoids: the user's history is gone and nothing on
            // screen says so, so they keep scanning into a bucket that empties on quit.
            // The failure is carried through to Settings instead.
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return Store(
                container: try! ModelContainer(for: ScanRecord.self, configurations: configuration),
                isTemporary: true,
                failure: error.localizedDescription
            )
        }
    }()

    struct Store {
        var container: ModelContainer
        /// True when history is being kept in memory and will vanish on quit.
        var isTemporary: Bool
        var failure: String?
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onAppear {
                    app.storageIsTemporary = store.isTemporary
                    app.storageFailure = store.failure
                }
        }
        .modelContainer(store.container)
    }
}
