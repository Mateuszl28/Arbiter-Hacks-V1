import Foundation

/// Picks the closest bundled ruleset to a coordinate.
///
/// Separated from CoreLocation entirely so the part that decides which city you get is
/// ordinary arithmetic that can be asserted on a desk, with no device, no permission
/// prompt and no simulated GPS.
enum NearestCity {
    struct Match: Sendable {
        var city: CityRuleset
        var distanceKm: Double

        /// How much to trust this.
        ///
        /// BinMate ships four cities. For a user in Madrid the nearest ruleset is
        /// Berlin, which is not merely imprecise but wrong — Spain sorts differently.
        /// Rather than silently assign it, the app says how far away the rules come
        /// from and lets the user judge.
        var confidence: Confidence {
            switch distanceKm {
            case ..<40: .inCity
            case ..<150: .nearby
            case ..<600: .sameRegion
            default: .farAway
            }
        }
    }

    enum Confidence: Sendable {
        /// Close enough that these are almost certainly the right rules.
        case inCity
        /// Same metropolitan area or a short drive; rules often still apply.
        case nearby
        /// Same country or neighbouring one; treat as a starting point.
        case sameRegion
        /// Nowhere near. The nearest ruleset is a guess, not an answer.
        case farAway

        var isTrustworthy: Bool { self == .inCity || self == .nearby }
    }

    /// Great-circle distance in kilometres.
    static func distanceKm(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double)
    ) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Nearest city with coordinates, or nil when no ruleset has any.
    static func match(
        latitude: Double,
        longitude: Double,
        in cities: [CityRuleset]
    ) -> Match? {
        cities
            .compactMap { city -> Match? in
                guard let cityLat = city.latitude, let cityLon = city.longitude else { return nil }
                return Match(
                    city: city,
                    distanceKm: distanceKm(
                        from: (latitude, longitude),
                        to: (cityLat, cityLon)
                    )
                )
            }
            .min { $0.distanceKm < $1.distanceKm }
    }
}

extension NearestCity.Match {
    /// What the user is told. Phrased so the uncertain cases read as uncertain.
    var summary: String {
        let rounded = distanceKm < 10
            ? String(format: "%.1f km", distanceKm)
            : "\(Int(distanceKm.rounded())) km"

        switch confidence {
        case .inCity:
            return "You appear to be in \(city.displayName)."
        case .nearby:
            return "\(city.displayName) is the closest ruleset, about \(rounded) away. Its rules usually apply nearby, but check."
        case .sameRegion:
            return "The closest ruleset is \(city.displayName), about \(rounded) away. Treat it as a starting point, not local law."
        case .farAway:
            return "BinMate has no ruleset near you. The closest is \(city.displayName), about \(rounded) away, and its rules probably do not apply where you are."
        }
    }
}
