import Foundation

/// The fuel figures a **new** shift starts out recording, as the driver's
/// settings currently hold them.
///
/// ## Defaults, and the one thing they are not
///
/// These are the driver's current preferences: the vehicle they selected and
/// what they last said a gallon costs. They are read at exactly one moment, when
/// a shift starts, and copied onto that shift. Afterwards the shift owns its
/// copy and this type has nothing more to do with it.
///
/// **Nothing historical ever reads these.** No estimate, rate, total, coverage
/// count or exported value is derived from a current default, and changing one
/// tomorrow changes no shift recorded today. That is the whole reason the
/// snapshot exists: a default that a finished shift kept reading would rewrite
/// its own history every time the driver changed vehicle or the price of fuel
/// moved.
///
/// ## Why the vehicle name travels with the pair
///
/// The fuel economy is what the estimate divides by; the name is what makes the
/// estimate legible a month later. A profile can be renamed or deleted, so a
/// shift that pointed at one would either lose its label or follow a change it
/// had nothing to do with. The name is therefore copied as a fact, exactly as
/// the economy is, and a shift stays intelligible with no profile behind it.
///
/// A name only ever accompanies an economy: it comes from a vehicle profile, and
/// a profile always has both.
nonisolated struct FuelDefaults: Equatable, Sendable {
    /// What the selected vehicle was called when the shift started, or `nil`
    /// when no vehicle was selected.
    let vehicleName: String?

    /// The pair a shift's estimate would be worked out under, in the type every
    /// fuel calculation in the app already takes.
    ///
    /// Reused rather than restated, so there is exactly one definition of "the
    /// two facts a fuel estimate is worked out from" in DashPilot.
    let assumptions: FuelAssumptions

    /// Nothing selected and no price recorded, which is what a driver who has
    /// never opened Settings has, and what every shift started before this
    /// existed began with.
    static let none = FuelDefaults(vehicleName: nil, assumptions: .none)

    init(vehicleName: String?, assumptions: FuelAssumptions) {
        self.vehicleName = vehicleName
        self.assumptions = assumptions
    }

    /// Convenience for the ordinary case: a selected vehicle and a current
    /// price, either of which may be absent.
    init(vehicleName: String?, milesPerGallon: Decimal?, gasPricePerGallon: Money?) {
        self.init(
            vehicleName: vehicleName,
            assumptions: FuelAssumptions(milesPerGallon: milesPerGallon, gasPricePerGallon: gasPricePerGallon)
        )
    }

    /// Whether there is anything to copy onto a shift at all.
    ///
    /// A shift started with nothing to copy is a shift recording no assumptions,
    /// which is exactly what every shift recorded before settings existed
    /// carries, and it reports that its estimate is unavailable rather than an
    /// estimate of `$0.00`.
    var hasAny: Bool { assumptions.hasAny }

    /// The vehicle name that truthfully accompanies a hand-entered fuel economy.
    ///
    /// The rule, and it is the one place this decision is written: a name says
    /// *which vehicle this economy describes*, so it may be recorded beside an
    /// economy only when that is the economy the named vehicle has. A driver who
    /// fills the editor from their current defaults and saves gets the name; one
    /// who types a different figure gets none, because DashPilot does not know
    /// which vehicle covers that many miles on a gallon.
    ///
    /// Returns `nil` for a missing economy, for one that is not the selected
    /// vehicle's, and when no vehicle is selected.
    func vehicleName(accompanying milesPerGallon: Decimal?) -> String? {
        guard let milesPerGallon, milesPerGallon == assumptions.milesPerGallon else { return nil }
        return vehicleName
    }
}

/// What a finished shift's fuel editor opens on, and whether that is the
/// shift's own record or a suggestion from somewhere else.
///
/// The order is the rule: the pair the shift already records; otherwise the
/// driver's current defaults, because they said what they are driving and what
/// fuel costs; otherwise the pair the most recent shift recorded. Anything but
/// the first is a **suggestion**: seeding a field records nothing, and the
/// shift holds no assumption until the driver saves.
nonisolated struct FuelAssumptionsSeed: Equatable, Sendable {
    let assumptions: FuelAssumptions

    /// Whether the fields hold figures this shift never recorded.
    let isSuggestion: Bool

    /// `mostRecent` is only read when neither the shift nor the defaults hold
    /// anything, so the store is not queried for a suggestion nobody needs.
    static func choose(
        recorded: FuelAssumptions,
        currentDefaults: FuelDefaults,
        mostRecent: () -> FuelAssumptions
    ) -> FuelAssumptionsSeed {
        if recorded.hasAny {
            return FuelAssumptionsSeed(assumptions: recorded, isSuggestion: false)
        }
        if currentDefaults.hasAny {
            return FuelAssumptionsSeed(assumptions: currentDefaults.assumptions, isSuggestion: true)
        }
        let recent = mostRecent()
        return FuelAssumptionsSeed(assumptions: recent, isSuggestion: recent.hasAny)
    }
}

/// How Settings states the current gas price: a recorded price with its unit,
/// a recorded zero as the zero it is, and no price as `Not set`, never as
/// `$0.00`.
nonisolated enum CurrentGasPriceWording {
    static func statement(_ price: Money?, locale: Locale) -> String {
        guard let price else { return notSet }
        return "\(price.formatted(locale: locale)) / gallon"
    }

    static func spoken(_ price: Money?, locale: Locale) -> String {
        guard let price else { return notSet }
        return "\(price.formatted(locale: locale)) per gallon"
    }

    static let notSet = "Not set"
}
