import CoreLocation
import Observation
import OSLog

/// Asks the system where the device is, once.
///
/// Deliberately a one-shot request rather than continuous updates: BinMate needs to know
/// which city's rules apply, which does not change while you are standing at a bin.
/// Tracking someone's movements to answer that would be a cost with no benefit.
///
/// The coordinate never leaves the device — it is used only to measure distance against
/// four numbers that ship inside the app.
@MainActor
@Observable
final class CityLocator: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case asking
        case denied
        case failed(String)
        case located(cityID: String, summary: String, trustworthy: Bool)
    }

    private(set) var state: State = .idle

    private let manager = CLLocationManager()
    private let library: RulesLibrary
    private let logger = Logger(subsystem: "app.binmate", category: "CityLocator")
    /// Called with the chosen city id once a fix resolves to a ruleset.
    private var onResolved: ((String) -> Void)?

    init(library: RulesLibrary) {
        self.library = library
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isBusy: Bool { state == .asking }

    func locate(onResolved: @escaping (String) -> Void) {
        self.onResolved = onResolved
        state = .asking

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            state = .denied
        default:
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .notDetermined:
                break
            case .denied, .restricted:
                self.state = .denied
            default:
                // Only chase a fix if the user actually asked for one.
                if self.state == .asking { manager.requestLocation() }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in self.resolve(latitude: coordinate.latitude, longitude: coordinate.longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.logger.error("Location failed: \(message, privacy: .public)")
            // A denial arrives here too on some paths; keep the clearer state.
            if self.state != .denied { self.state = .failed(message) }
        }
    }

    // MARK: - Resolution

    func resolve(latitude: Double, longitude: Double) {
        guard let match = NearestCity.match(latitude: latitude, longitude: longitude, in: library.cities) else {
            state = .failed("No city ruleset has coordinates to compare against.")
            return
        }

        state = .located(
            cityID: match.city.id,
            summary: match.summary,
            trustworthy: match.confidence.isTrustworthy
        )

        // Switch automatically only when the match is close enough to be believable.
        // Further away, the summary explains the situation and the user decides.
        if match.confidence.isTrustworthy {
            onResolved?(match.city.id)
        }
    }
}
