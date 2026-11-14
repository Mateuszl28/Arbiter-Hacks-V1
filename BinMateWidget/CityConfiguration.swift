import AppIntents

/// A city the user can pick on the widget itself.
///
/// This exists to remove a dependency that could not be satisfied. Following the app's
/// selected city needs the `group.app.binmate` App Group, and App Group entitlements
/// require a provisioning profile — so an unsigned or ad-hoc build gets none, and the
/// widget silently showed whichever city happened to be first. Letting the widget carry
/// its own choice works in every build, needs no entitlement, and is arguably better
/// behaviour anyway: someone who travels can keep one widget per city.
///
/// The shared default is still read as the *starting* value, so a freshly added widget
/// already shows the right place when the entitlement is available.
struct CityEntity: AppEntity {
    var id: String
    var name: String
    var regionCode: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "City" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(regionCode)")
    }

    static var defaultQuery = CityEntityQuery()

    init(id: String, name: String, regionCode: String) {
        self.id = id
        self.name = name
        self.regionCode = regionCode
    }

    init(ruleset: CityRuleset) {
        self.init(id: ruleset.id, name: ruleset.displayName, regionCode: ruleset.region)
    }
}

/// Offers the bundled cities to the widget's configuration sheet.
///
/// Reads the same rulesets the app does, so the list can never drift from what the app
/// can actually sort against.
struct CityEntityQuery: EntityQuery {
    /// A `var` so the test suite can point it at the built app bundle. In the extension
    /// `Bundle.main` is the appex, which carries its own copy of the rules; in a host
    /// harness it is the test binary, which carries none — the same seam every other
    /// loader in this project already has.
    static var library = RulesLibrary.loadBundled()

    func entities(for identifiers: [CityEntity.ID]) async throws -> [CityEntity] {
        identifiers.compactMap { id in
            Self.library.city(id: id).map(CityEntity.init(ruleset:))
        }
    }

    func suggestedEntities() async throws -> [CityEntity] {
        Self.library.cities.map(CityEntity.init(ruleset:))
    }

    /// What a newly added widget shows before the user configures anything: the city
    /// chosen in the app when that is readable, otherwise the first bundled one.
    func defaultResult() async -> CityEntity? {
        let stored = SharedDefaults.selectedCityID() ?? ""
        let city = Self.library.city(id: stored) ?? Self.library.fallbackCity
        return city.map(CityEntity.init(ruleset:))
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose City"
    static var description = IntentDescription("Which city's bins this widget shows.")

    @Parameter(title: "City")
    var city: CityEntity?

    init() {}

    init(city: CityEntity?) {
        self.city = city
    }
}
