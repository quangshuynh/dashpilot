import Foundation

/// Which vehicle assumptions the **next** shift will record, shown beside the
/// control that starts it.
///
/// ## It is the start's own read, and never a second one
///
/// Built from a ``FuelDefaults``, which is exactly the value
/// ``ShiftService/startShift(at:)`` copies onto a new shift, and that value is
/// produced by one rule, ``SettingsService/fuelDefaults(settings:vehicles:)``,
/// whichever of the two callers asks. There is no preview snapshot here that
/// could drift from the real one: what this says before the tap is what the
/// shift records at it.
///
/// ## Before the start and after it are different questions
///
/// Before a shift exists, the driver's current settings are the right source,
/// because they are the figures about to be copied. Once it starts, the shift's
/// own snapshot is the only source, read through ``ShiftVehicleContext``, and
/// nothing here is consulted again. A driver who changes vehicle after starting
/// changes what *this* type says and nothing about the shift in progress.
///
/// ## Missing is said, not filled
///
/// No vehicle selected reads as that, not as a vehicle chosen on the driver's
/// behalf and not as `0 MPG`. A price with no vehicle says both halves as they
/// are. None of it refuses a start: a shift started with nothing to copy records
/// no assumptions, as it always has.
///
/// ## It is a label, not an input
///
/// Nothing is persisted by reading it, and no estimate, rate, total, coverage
/// count or exported value is derived from it.
nonisolated struct NextShiftVehicleContext: Equatable, Sendable {
    /// The selected vehicle's name, or `nil` where none is selected.
    let vehicleName: String?

    /// The selected vehicle's fuel economy, or `nil` where none is selected.
    let milesPerGallon: Decimal?

    /// The current gas price, or `nil` where none is set.
    let gasPricePerGallon: Money?

    init(defaults: FuelDefaults) {
        vehicleName = defaults.vehicleName
        milesPerGallon = defaults.assumptions.milesPerGallon
        gasPricePerGallon = defaults.assumptions.gasPricePerGallon
    }

    /// Whether a vehicle is selected, which is the fact the row leads with.
    var hasVehicle: Bool { vehicleName != nil }

    /// The line the row leads with: the selected vehicle's name, or the
    /// statement that there is not one.
    var title: String { vehicleName ?? "No vehicle selected" }

    /// The figures under the name, in the words Settings already prints them
    /// in, or `nil` where neither is known.
    ///
    /// `"34 MPG · Gas $3.29/gal"`, either half alone, or nothing. A missing half
    /// is left out rather than written as zero.
    func detail(locale: Locale = .autoupdatingCurrent) -> String? {
        var parts: [String] = []
        if let milesPerGallon {
            parts.append("\(MilesPerGallonInput(locale: locale).text(for: milesPerGallon)) MPG")
        }
        if let gasPricePerGallon {
            parts.append("Gas \(gasPricePerGallon.formatted(locale: locale))/gal")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a listener is told this row is about. Distinct from the running
    /// shift's `"Shift vehicle"`, because the two are about different shifts.
    var spokenLabel: String { "Next shift vehicle" }

    /// The facts as one spoken value, with every unit spelled out:
    /// `"2020 Honda Civic, 34 miles per gallon, gas $3.29 per gallon"`.
    func spokenValue(locale: Locale = .autoupdatingCurrent) -> String {
        var parts: [String] = [vehicleName ?? "No vehicle selected for the next shift"]
        if let milesPerGallon {
            parts.append("\(MilesPerGallonInput(locale: locale).text(for: milesPerGallon)) miles per gallon")
        }
        if let gasPricePerGallon {
            parts.append("gas \(gasPricePerGallon.formatted(locale: locale)) per gallon")
        }
        return parts.joined(separator: ", ")
    }
}
