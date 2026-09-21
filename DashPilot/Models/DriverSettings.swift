import Foundation
import SwiftData

/// Errors raised when a settings change would violate the model's invariants.
nonisolated enum DriverSettingsError: Error, Equatable {
    /// A negative gas price. Zero is allowed and means the fuel was recorded as
    /// costing nothing; a negative price is not a thing a pump charges.
    case negativeGasPrice
}

nonisolated extension DriverSettingsError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .negativeGasPrice:
            "A gas price cannot be a negative amount. Enter what a gallon costs."
        }
    }
}

/// The driver's current preferences: which vehicle they are working in, and what
/// they last said a gallon of fuel costs.
///
/// ## One row, and why it is in the store rather than in `UserDefaults`
///
/// DashPilot has no preferences layer and deliberately still does not have a
/// general one. What it has is this: a single row in the same local store every
/// other fact lives in, so that a preference travels with a backup, is covered
/// by the same migration discipline as everything else, and cannot drift out of
/// step with the store the way a parallel defaults database can. The identifier
/// is a constant and is unique, so the store holds **at most one** of these by
/// construction rather than by a rule somebody has to keep.
///
/// ## Everything here is a default for the *next* shift
///
/// Nothing derived reads this row. Not an estimate, not a rate, not a total, not
/// a coverage count, not an exported value, not a period figure. It is read at
/// exactly one moment — when a shift starts — and copied onto that shift, which
/// then owns its copy forever.
///
/// The consequence is the invariant the whole feature is built to keep:
/// **changing a setting tomorrow changes nothing recorded today.** A driver who
/// puts today's gas price in here has not restated what they paid last week, and
/// one who switches vehicle has not changed what last Tuesday's shift consumed.
///
/// ## The selected vehicle is an identifier, not a relationship
///
/// ``selectedVehicleID`` holds a ``VehicleProfile/id`` rather than a SwiftData
/// reference. Deleting a profile then leaves an identifier that resolves to
/// nothing, which reads as *no vehicle selected* — a state the app already knows
/// how to be in and shows plainly. A relationship would instead make deleting a
/// profile a write to this row, and would invite exactly the mandatory link
/// between a driver's history and a row they are invited to delete that this
/// design refuses.
@Model
nonisolated final class DriverSettings {
    /// The identifier every settings row has, so that there is one.
    ///
    /// A constant rather than a fresh `UUID`, combined with the unique attribute
    /// below: two attempts to create the row resolve to the same row instead of
    /// producing a second set of preferences that half the app would read.
    static let singletonID = UUID(uuidString: "5B0E2F0A-3C1D-4E6B-9A77-0D2C8F41A3E5")!

    @Attribute(.unique) private(set) var id: UUID

    /// What the driver says a gallon currently costs, or `nil` when they have
    /// not said.
    ///
    /// Zero is allowed and is a different fact from missing, exactly as it is on
    /// a shift: an explicit zero says the fuel is recorded as costing nothing,
    /// and `nil` says nobody has written a price down. A shift started while
    /// this is `nil` records no gas price and reports which half of its estimate
    /// is missing, rather than an estimate of `$0.00`.
    ///
    /// **This is a convenience, not a price history.** DashPilot records one
    /// current figure the driver typed. It keeps no series of prices, fetches
    /// nothing from a network, knows no station and derives nothing from where
    /// the device is.
    private(set) var gasPricePerGallonAmount: Decimal?

    /// The ``VehicleProfile/id`` of the vehicle the driver is working in, or
    /// `nil` when none is selected or the selected one has since been deleted.
    private(set) var selectedVehicleID: UUID?

    init(
        id: UUID = DriverSettings.singletonID,
        gasPricePerGallon: Money? = nil,
        selectedVehicleID: UUID? = nil
    ) {
        self.id = id
        self.gasPricePerGallonAmount = gasPricePerGallon?.amount
        self.selectedVehicleID = selectedVehicleID
    }

    /// The current gas price, in the app's money vocabulary.
    var gasPricePerGallon: Money? { gasPricePerGallonAmount.map(Money.init(amount:)) }

    /// Records what a gallon currently costs.
    ///
    /// - Throws: ``DriverSettingsError/negativeGasPrice``.
    func setGasPricePerGallon(_ price: Money) throws {
        guard price.amount >= 0 else { throw DriverSettingsError.negativeGasPrice }
        gasPricePerGallonAmount = price.amount
    }

    /// Removes the current gas price, returning it to unrecorded.
    ///
    /// Distinct from recording zero: afterwards a shift that starts records no
    /// gas price at all, rather than one of `$0.00`.
    func clearGasPricePerGallon() {
        gasPricePerGallonAmount = nil
    }

    /// Selects the vehicle new shifts are recorded under, or clears the
    /// selection when passed `nil`.
    func selectVehicle(id: UUID?) {
        selectedVehicleID = id
    }
}
