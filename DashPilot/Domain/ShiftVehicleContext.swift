import Foundation

/// Which vehicle assumptions the shift in front of the driver is using.
///
/// ## It reads a snapshot, and it is never a lookup
///
/// The two facts here are the ones the **shift** recorded when it started, taken
/// from `Shift.fuelVehicleName` and `Shift.fuelMilesPerGallonValue`. Nothing in
/// this type reaches `DriverSettings`, `VehicleProfile` or
/// `SettingsService.currentFuelDefaults()`, and that is the whole of what makes
/// it truthful: a driver who changes their selected vehicle at lunchtime has not
/// changed what this shift has already been estimated under, and a screen that
/// filled the gap from the current selection would say the shift was worked in a
/// vehicle nobody recorded.
///
/// So a shift that recorded nothing says it recorded nothing. It does not
/// borrow, and it does not guess.
///
/// ## The question it answers
///
/// *Which vehicle is this shift using?* A driver with two vehicles who forgot to
/// switch before starting has no other way to find out without leaving the
/// driving screen for Settings, and Settings would answer a different question:
/// which vehicle the **next** shift will record.
///
/// ## It is a label, not an input
///
/// No estimate, rate, total or coverage count reads any of this. The gas price
/// is deliberately absent: it belongs to the fuel estimate a finished shift
/// reports, and a price on the one screen a driver looks at while working would
/// be a figure with nothing to do on it.
nonisolated struct ShiftVehicleContext: Equatable, Sendable {
    /// What the vehicle was called when the shift started, or `nil` where the
    /// shift recorded no name.
    let vehicleName: String?

    /// The fuel economy the shift recorded, or `nil` where it recorded none.
    ///
    /// Independent of the name rather than paired with it, because the store
    /// really can hold one without the other: a driver with a current gas price
    /// and no selected vehicle starts a shift with a price and nothing else.
    let milesPerGallon: Decimal?

    /// A shift that recorded neither, which is what every shift started before
    /// vehicle profiles existed carries and what a driver who has never opened
    /// Settings still starts.
    static let none = ShiftVehicleContext(vehicleName: nil, milesPerGallon: nil)

    init(vehicleName: String?, milesPerGallon: Decimal?) {
        self.vehicleName = vehicleName
        self.milesPerGallon = milesPerGallon
    }

    /// Whether the shift recorded anything about the vehicle at all.
    var isRecorded: Bool { vehicleName != nil || milesPerGallon != nil }

    /// The line the screen leads with: the vehicle's name, or the statement that
    /// there is not one.
    ///
    /// **Never the currently selected vehicle.** The missing case is said rather
    /// than filled, because "no vehicle recorded" and "the vehicle you have
    /// selected today" are different facts and only one of them is about this
    /// shift.
    var title: String { vehicleName ?? "No vehicle recorded" }

    /// The figure under the name, in the words Settings already prints it in, or
    /// `nil` where the shift recorded no economy.
    func economyStatement(locale: Locale = .autoupdatingCurrent) -> String? {
        milesPerGallon.map { "\(MilesPerGallonInput(locale: locale).text(for: $0)) MPG" }
    }

    /// What a listener is told this row is about.
    var spokenLabel: String { "Shift vehicle" }

    /// The two facts as one spoken value: `"2020 Honda Civic, 34 miles per
    /// gallon"`.
    ///
    /// The unit is spelled out, exactly as the Settings row spells it out, and
    /// for the same reason: `MPG` reads well and hears badly, and a listener has
    /// no caption in view to read the unit off.
    func spokenValue(locale: Locale = .autoupdatingCurrent) -> String {
        guard let milesPerGallon else {
            return vehicleName ?? "No vehicle recorded for this shift"
        }
        let economy = "\(MilesPerGallonInput(locale: locale).text(for: milesPerGallon)) miles per gallon"
        guard let vehicleName else { return economy }
        return "\(vehicleName), \(economy)"
    }
}
