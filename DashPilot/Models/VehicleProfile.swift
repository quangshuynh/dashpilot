import Foundation
import SwiftData

/// Errors raised when a vehicle profile would violate the model's invariants.
nonisolated enum VehicleProfileError: Error, Equatable {
    /// The name broke ``VehicleName``'s rule.
    case invalidName(VehicleNameError)
    /// A fuel economy of zero or less. It is the divisor of every estimate a
    /// shift started under this profile will carry, and there is no truthful
    /// reading of a vehicle that covers no distance on a gallon.
    case invalidFuelEconomy
}

nonisolated extension VehicleProfileError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidName(error):
            error.errorDescription
        case .invalidFuelEconomy:
            "Miles per gallon has to be more than zero. It is what DashPilot divides the recorded miles by."
        }
    }
}

/// One vehicle the driver works in, kept so its fuel economy is typed once
/// rather than on every shift.
///
/// ## It is a preference, not history
///
/// This row is a **current** fact about the driver, in the way a shift is a
/// **past** fact about their work, and the distinction is the whole design. A
/// profile can be renamed, corrected and deleted freely, because nothing derived
/// reads it: when a shift starts, the selected profile's name and fuel economy
/// are **copied onto that shift**, and every estimate, total and exported value
/// is derived from the copy. Editing this row afterwards changes no figure the
/// driver has already seen, and deleting it leaves every shift it ever started
/// exactly as it was.
///
/// There is deliberately **no relationship to ``Shift``**, for that reason and
/// for one more: a relationship would make a driver's history depend on a row
/// they are invited to delete. What a shift needs from a vehicle is two facts,
/// and it holds them itself.
///
/// ## What it deliberately is not
///
/// Two fields, and the list of what is absent is the point. There is no VIN, no
/// plate, no make, model or trim lookup, no odometer, no service schedule, no
/// insurance record, no tyre history, no purchase price and no depreciation.
/// DashPilot estimates fuel over recorded mileage; a vehicle profile exists to
/// hold the number that estimate divides by, and nothing else has been added
/// because it would look tidy beside it.
///
/// ## Privacy
///
/// The name is free text the driver typed and is never logged, exactly as a
/// pickup place name and an expense note are never logged. The fuel economy is
/// never logged either: it describes the driver's vehicle.
@Model
nonisolated final class VehicleProfile {
    /// Stable identifier.
    ///
    /// It is what ``DriverSettings`` points at to record the selected vehicle,
    /// deliberately instead of a SwiftData relationship: a dangling identifier
    /// resolves to "no vehicle selected", which is a state the app already knows
    /// how to be in, whereas a relationship makes deleting a profile a change to
    /// another row.
    @Attribute(.unique) private(set) var id: UUID

    /// What the driver calls this vehicle. Always the trimmed, non-empty,
    /// length-checked form, because ``VehicleName`` is the only way one is set.
    private(set) var name: String

    /// The vehicle's fuel economy in miles per gallon.
    ///
    /// Always greater than zero: it is the divisor of every estimate a shift
    /// started under this profile carries, and both the initialiser and the
    /// editor refuse anything else.
    ///
    /// A `Decimal` rather than a ``Money``, for the reason
    /// ``FuelAssumptions/milesPerGallon`` is one: a ratio is not currency.
    private(set) var milesPerGallonValue: Decimal

    /// When the profile was created, which is the order the list is drawn in.
    ///
    /// A stable order that does not move when a profile is renamed. Sorting by
    /// name would reorder the list under a driver's finger mid-edit, and sorting
    /// by "last used" would need a write on every shift start to record it.
    private(set) var createdAt: Date

    /// - Throws: ``VehicleProfileError`` naming the first rule the values break.
    ///   Nothing partially valid is ever constructed.
    init(
        id: UUID = UUID(),
        name: String,
        milesPerGallon: Decimal,
        createdAt: Date = .now
    ) throws {
        let checkedName: String
        do {
            checkedName = try VehicleName.name(from: name)
        } catch {
            throw VehicleProfileError.invalidName(error)
        }
        guard milesPerGallon > 0 else { throw VehicleProfileError.invalidFuelEconomy }

        self.id = id
        self.name = checkedName
        self.milesPerGallonValue = milesPerGallon
        self.createdAt = createdAt
    }

    /// The fuel economy, in the vocabulary the rest of the app reads it in.
    var milesPerGallon: Decimal { milesPerGallonValue }

    /// Corrects both facts at once, or neither.
    ///
    /// Both are checked before either is written, so a profile whose name is
    /// fixed and whose economy is mistyped keeps the pair it already had. The
    /// same shape as ``Shift/setFuelAssumptions(milesPerGallon:gasPricePerGallon:vehicleName:)``,
    /// and for the same reason.
    ///
    /// **This changes no shift.** A shift that started under this profile holds
    /// its own copy of both values.
    ///
    /// - Throws: ``VehicleProfileError``.
    func update(name: String, milesPerGallon: Decimal) throws {
        let checkedName: String
        do {
            checkedName = try VehicleName.name(from: name)
        } catch {
            throw VehicleProfileError.invalidName(error)
        }
        guard milesPerGallon > 0 else { throw VehicleProfileError.invalidFuelEconomy }

        self.name = checkedName
        self.milesPerGallonValue = milesPerGallon
    }

    /// The defaults a shift started under this vehicle would record, with
    /// whatever gas price the driver currently has.
    ///
    /// The one place a profile becomes a ``FuelDefaults``, so the name and the
    /// economy cannot be copied apart from one another.
    func defaults(gasPricePerGallon: Money?) -> FuelDefaults {
        FuelDefaults(
            vehicleName: name,
            milesPerGallon: milesPerGallonValue,
            gasPricePerGallon: gasPricePerGallon
        )
    }
}
