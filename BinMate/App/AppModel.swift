import Foundation
import Observation
import SwiftUI

/// App-wide state: which city's rules are in force, what was loaded, and the user's
/// handful of preferences.
@MainActor
@Observable
final class AppModel {
    let library: RulesLibrary
    let samples: SampleProducts
    let client = OpenFoodFactsClient()

    /// Selected city, persisted across launches.
    var selectedCityID: String {
        // Written through SharedDefaults so the widget sees the same choice.
        didSet { SharedDefaults.setSelectedCityID(selectedCityID) }
    }

    /// Hard offline mode. Exposed in Settings because a demo that cannot be made
    /// deterministic is a demo that breaks on stage.
    var offlineOnly: Bool {
        didSet { UserDefaults.standard.set(offlineOnly, forKey: Keys.offline) }
    }

    /// Set at launch when the on-disk history store could not be opened and the app fell
    /// back to memory. Surfaced in Settings so the user is not left scanning into a
    /// bucket that empties when they quit.
    var storageIsTemporary = false
    var storageFailure: String?

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }

    private enum Keys {
        static let city = "selectedCityID"
        static let offline = "offlineOnly"
        static let onboarded = "hasCompletedOnboarding"
    }

    init(library: RulesLibrary = .loadBundled(), samples: SampleProducts = .loadBundled()) {
        self.library = library
        self.samples = samples

        let defaults = UserDefaults.standard
        let stored = SharedDefaults.selectedCityID()
        // Fall back to the first available city rather than trusting a stored id that
        // may refer to a ruleset removed in an update.
        self.selectedCityID = library.city(id: stored ?? "")?.id
            ?? library.fallbackCity?.id
            ?? ""
        self.offlineOnly = defaults.bool(forKey: Keys.offline)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
    }

    var city: CityRuleset? {
        library.city(id: selectedCityID)
    }

    var cities: [CityRuleset] { library.cities }

    /// Engine for the active city. `nil` only if no ruleset loaded at all, which the
    /// UI treats as a hard error rather than pretending to sort.
    var engine: RulesEngine? {
        city.map(RulesEngine.init(ruleset:))
    }

    func engine(for cityID: String) -> RulesEngine? {
        library.city(id: cityID).map(RulesEngine.init(ruleset:))
    }

    /// Problems found while loading bundled data, shown in Settings.
    var loadProblems: [String] { library.problems + samples.problems }
}
