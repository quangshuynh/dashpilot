import Foundation
import OSLog
import SwiftData

/// Failures raised when a settings change cannot be written.
nonisolated enum SettingsError: Error {
    /// The model refused the values: an empty or over-long name, or a fuel
    /// economy of zero or less.
    case invalidVehicle(VehicleProfileError)
    /// The model refused the gas price.
    case invalidSettings(DriverSettingsError)
    /// The profile being edited, selected or deleted is no longer a row the
    /// store holds.
    case vehicleNoLongerExists
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension SettingsError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidVehicle(lhsError), .invalidVehicle(rhsError)): lhsError == rhsError
        case let (.invalidSettings(lhsError), .invalidSettings(rhsError)): lhsError == rhsError
        case (.vehicleNoLongerExists, .vehicleNoLongerExists): true
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension SettingsError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidVehicle(error):
            error.errorDescription
        case let .invalidSettings(error):
            error.errorDescription
        case .vehicleNoLongerExists:
            "That vehicle is no longer in DashPilot, so nothing was changed."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the setting was not changed."
        }
    }
}

/// The driver's reusable preferences: their vehicles, which one they are working
/// in, and what a gallon currently costs.
///
/// ## What it owns
///
/// The writes to ``VehicleProfile`` and ``DriverSettings``, and one read that
/// matters: ``currentFuelDefaults()``, which is what a starting shift copies.
///
/// ## What it deliberately does not do
///
/// - **It never touches a recorded shift.** Not when a profile is edited, not
///   when one is deleted, not when the selected vehicle changes and not when the
///   gas price moves. There is no backfill anywhere in this type, and the tests
///   that matter most here assert an absence: a shift recorded yesterday has the
///   same fuel economy, gas price, vehicle name, estimate and net after every
///   one of those operations.
/// - **It fetches nothing from a network.** There is no price lookup, no station
///   search, no location-derived price and no vehicle database. The gas price is
///   a figure the driver typed, and DashPilot has no other source for one.
/// - **It keeps no history.** One current price, not a series; one selected
///   vehicle, not a record of which vehicle was selected when. What a shift was
///   worked under is recorded on that shift, which is the only place it means
///   anything.
///
/// The type is `@MainActor` isolated and operations run to completion without
/// suspending, exactly as the other services do.
@MainActor
struct SettingsService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reading

    /// The settings row, creating it the first time it is asked for.
    ///
    /// The row is a singleton by its identifier rather than by a rule: the
    /// constant ``DriverSettings/singletonID`` is unique in the store, so a race
    /// between two creations resolves to one row rather than to two sets of
    /// preferences half the app would read.
    ///
    /// - Throws: ``SettingsError/storeUnavailable(underlying:)``.
    @discardableResult
    func settings() throws -> DriverSettings {
        if let existing = try existingSettings() { return existing }

        let created = DriverSettings()
        context.insert(created)
        try save(describing: "create settings")
        return created
    }

    /// The settings row if the store already holds one, without creating it.
    ///
    /// Read by anything that must not write on a read path, which is why
    /// ``currentFuelDefaults()`` uses it: starting a shift must not fail, or
    /// create a row, because a driver has never opened Settings.
    func existingSettings() throws -> DriverSettings? {
        let id = DriverSettings.singletonID
        var descriptor = FetchDescriptor<DriverSettings>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            AppLog.settings.error("Failed to read the driver's settings: \(error)")
            throw SettingsError.storeUnavailable(underlying: error)
        }
    }

    /// Every vehicle profile, oldest first.
    ///
    /// The order a driver added them, which is stable under renaming. Returns an
    /// empty list on a read failure rather than throwing: a settings screen with
    /// no vehicles on it is a screen the app already knows how to draw.
    func vehicleProfiles() -> [VehicleProfile] {
        let descriptor = FetchDescriptor<VehicleProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.settings.error("Failed to read the vehicle profiles: \(error)")
            return []
        }
    }

    /// The vehicle new shifts are currently recorded under, or `nil` when none
    /// is selected or the selected one has since been deleted.
    ///
    /// A deleted selection resolving to `nil` rather than to an error is the
    /// point of storing an identifier: *no vehicle selected* is a state the app
    /// is designed to be in, and it is what a driver who deletes the vehicle
    /// they were using should land in.
    func selectedVehicle() -> VehicleProfile? {
        guard let id = (try? existingSettings())??.selectedVehicleID else { return nil }
        var descriptor = FetchDescriptor<VehicleProfile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// What a shift starting now would record.
    ///
    /// **This is the only read of the driver's preferences that reaches a
    /// recorded fact**, and it reaches it exactly once, at
    /// ``ShiftService/startShift(at:)``. Everything after that is derived from
    /// the copy the shift holds.
    ///
    /// Returns ``FuelDefaults/none`` when nothing is set and on a read failure.
    /// A shift that starts with nothing to copy is a shift recording no
    /// assumptions, which is the ordinary state of every shift recorded before
    /// this existed, and is never an estimate of `$0.00`.
    func currentFuelDefaults() -> FuelDefaults {
        Self.fuelDefaults(
            settings: (try? existingSettings()) ?? nil,
            vehicles: selectedVehicle().map { [$0] } ?? []
        )
    }

    /// The one rule that turns the driver's preferences into what a shift
    /// starting now would record.
    ///
    /// Shared by ``currentFuelDefaults()``, which ``ShiftService/startShift(at:)``
    /// copies, and by the Home screen's ``NextShiftVehicleContext``, which draws
    /// the same figures from rows it already observes. Keeping it in one place
    /// is what makes the row beside `Start Shift` say exactly what the shift
    /// will record, rather than a second reading of the settings that could
    /// drift from the first.
    ///
    /// The selected vehicle is the profile whose identifier the settings hold.
    /// None selected, or an identifier no profile in `vehicles` carries, is no
    /// vehicle: nothing is chosen on the driver's behalf, and a deleted profile
    /// is never borrowed.
    static func fuelDefaults(settings: DriverSettings?, vehicles: [VehicleProfile]) -> FuelDefaults {
        let price = settings?.gasPricePerGallon
        guard let id = settings?.selectedVehicleID,
              let vehicle = vehicles.first(where: { $0.id == id })
        else {
            return FuelDefaults(vehicleName: nil, milesPerGallon: nil, gasPricePerGallon: price)
        }
        return vehicle.defaults(gasPricePerGallon: price)
    }

    // MARK: Vehicles

    /// Creates a vehicle profile.
    ///
    /// The first profile a driver creates is selected automatically, because a
    /// driver who has entered exactly one vehicle has told the app which one
    /// they work in, and leaving it unselected would mean their next shift
    /// records nothing they would understand as a choice. Every later one is
    /// selected only by asking.
    ///
    /// - Throws: ``SettingsError/invalidVehicle(_:)`` or
    ///   ``SettingsError/storeUnavailable(underlying:)``.
    @discardableResult
    func addVehicle(name: String, milesPerGallon: Decimal, createdAt: Date = .now) throws -> VehicleProfile {
        let profile: VehicleProfile
        do {
            profile = try VehicleProfile(name: name, milesPerGallon: milesPerGallon, createdAt: createdAt)
        } catch let error as VehicleProfileError {
            AppLog.settings.notice("Refused a vehicle profile: \(String(describing: error), privacy: .public)")
            throw SettingsError.invalidVehicle(error)
        }

        context.insert(profile)

        let isFirst = vehicleProfiles().count <= 1
        if isFirst {
            try settings().selectVehicle(id: profile.id)
        }

        try save(describing: "add a vehicle")
        AppLog.settings.info("Vehicle profile added, selected: \(isFirst, privacy: .public)")
        return profile
    }

    /// Corrects a vehicle's name and fuel economy.
    ///
    /// **No shift moves.** A shift started under this profile holds its own copy
    /// of both values, so a driver correcting a fuel economy they mistyped is
    /// changing what their *next* shift records and nothing else. That is
    /// deliberate and is stated on the screen: the alternative, rewriting the
    /// estimates of every shift the profile ever started, would silently restate
    /// history the driver never revisited.
    ///
    /// - Throws: ``SettingsError``.
    func updateVehicle(_ profile: VehicleProfile, name: String, milesPerGallon: Decimal) throws {
        guard !profile.isDeleted else { throw SettingsError.vehicleNoLongerExists }

        do {
            try profile.update(name: name, milesPerGallon: milesPerGallon)
        } catch let error as VehicleProfileError {
            AppLog.settings.notice("Refused a vehicle edit: \(String(describing: error), privacy: .public)")
            throw SettingsError.invalidVehicle(error)
        }

        try save(describing: "update a vehicle")
        AppLog.settings.info("Vehicle profile updated")
    }

    /// Deletes a vehicle profile.
    ///
    /// **Every shift survives it untouched**, including the shifts started under
    /// this very profile: each holds its own copy of the name and the economy,
    /// and there is no relationship for a delete to cascade along. A shift
    /// started under a vehicle that no longer exists still says which vehicle it
    /// was and still produces the same estimate.
    ///
    /// If the deleted profile was the selected one, the selection is cleared in
    /// the same save, so the store never records a selection pointing at nothing.
    ///
    /// - Throws: ``SettingsError``.
    func deleteVehicle(_ profile: VehicleProfile) throws {
        guard !profile.isDeleted else { throw SettingsError.vehicleNoLongerExists }

        let wasSelected = (try existingSettings())?.selectedVehicleID == profile.id
        if wasSelected {
            try settings().selectVehicle(id: nil)
        }
        context.delete(profile)

        try save(describing: "delete a vehicle")
        AppLog.settings.info("Vehicle profile deleted, was selected: \(wasSelected, privacy: .public)")
    }

    /// Selects the vehicle new shifts are recorded under, or clears the
    /// selection.
    ///
    /// **No shift moves**, for the reason an edit moves none: the shifts already
    /// recorded hold their own copies.
    ///
    /// - Throws: ``SettingsError``.
    func selectVehicle(_ profile: VehicleProfile?) throws {
        if let profile, profile.isDeleted { throw SettingsError.vehicleNoLongerExists }

        try settings().selectVehicle(id: profile?.id)
        try save(describing: "select a vehicle")
        AppLog.settings.info("Selected vehicle \(profile == nil ? "cleared" : "changed", privacy: .public)")
    }

    // MARK: Fuel defaults

    /// Records what a gallon currently costs.
    ///
    /// **No shift moves.** A shift recorded last week holds the price it was
    /// estimated under, and this changes what the next one starts with. The
    /// screen says so, because it is the one thing about this field a driver
    /// could reasonably assume the other way.
    ///
    /// - Throws: ``SettingsError``.
    func setGasPricePerGallon(_ price: Money) throws {
        let settings = try settings()
        // Read before the write, so the log can say what happened without ever
        // holding the figure it happened to.
        let isFirst = settings.gasPricePerGallon == nil

        do {
            try settings.setGasPricePerGallon(price)
        } catch let error as DriverSettingsError {
            AppLog.settings.notice("Refused a gas price: \(String(describing: error), privacy: .public)")
            throw SettingsError.invalidSettings(error)
        }

        try save(describing: "set the gas price")
        AppLog.settings.info("Current gas price \(isFirst ? "recorded" : "updated", privacy: .public)")
    }

    /// Removes the current gas price, returning it to unrecorded.
    ///
    /// - Throws: ``SettingsError``.
    func clearGasPricePerGallon() throws {
        try settings().clearGasPricePerGallon()
        try save(describing: "clear the gas price")
        AppLog.settings.info("Current gas price removed")
    }

    // MARK: Saving

    /// Saves, and rolls back if the store refuses.
    ///
    /// `operation` is a fixed word naming what was attempted. It is written to
    /// the log; a name, a fuel economy and a price never are.
    private func save(describing operation: StaticString) throws {
        do {
            try context.save()
        } catch {
            // The pending change is discarded: a settings screen must not show a
            // preference the store does not hold, or a later shift would start
            // under one thing while the driver was shown another.
            context.rollback()
            AppLog.settings.error("Failed to \(operation, privacy: .public): \(error)")
            throw SettingsError.storeUnavailable(underlying: error)
        }
    }
}
