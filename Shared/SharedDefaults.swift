import Foundation

/// The small amount of state the app and its widget both need.
///
/// Only the selected city lives here. History stays in the app's own SwiftData store and
/// is deliberately *not* shared: a widget has no business reading a list of what someone
/// throws away, and moving the store would mean migrating it, which is the one thing
/// recently shown to be worth not doing casually.
enum SharedDefaults {
    static let appGroup = "group.app.binmate"
    static let selectedCityKey = "selectedCityID"

    /// The shared suite, falling back to standard defaults when the App Group is
    /// unavailable — an unsigned build, or a target without the entitlement. The app
    /// then still works; only the widget goes stale.
    static var store: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Reads the selected city, preferring the shared suite but accepting a value left
    /// behind in standard defaults by a build that predates the App Group.
    static func selectedCityID() -> String? {
        if let shared = store.string(forKey: selectedCityKey), !shared.isEmpty {
            return shared
        }
        return UserDefaults.standard.string(forKey: selectedCityKey)
    }

    /// Writes to both, so a downgrade or a missing entitlement cannot strand the choice
    /// somewhere only one of the two can see it.
    static func setSelectedCityID(_ id: String) {
        store.set(id, forKey: selectedCityKey)
        UserDefaults.standard.set(id, forKey: selectedCityKey)
    }
}
