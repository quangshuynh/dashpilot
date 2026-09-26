import Foundation

/// The vehicle assumptions a **completed** shift recorded, as History shows them.
///
/// ## A snapshot, read and never looked up
///
/// Every value here is one of the shift's own three columns: the name, the fuel
/// economy and the gas price it recorded. Nothing reaches `DriverSettings`,
/// `VehicleProfile` or `SettingsService`, so a profile renamed or deleted since,
/// a different selection and a new current price all leave a finished shift
/// saying exactly what it said. That is the whole point of the snapshot.
///
/// ## Why this is not ``ShiftVehicleContext``
///
/// That type describes the shift being worked, and deliberately leaves the gas
/// price out of a screen a driver reads while driving. A finished shift's price
/// is one of the two figures its fuel estimate is worked out from, so here it
/// belongs beside the vehicle. The name and economy come through
/// ``Shift/vehicleContext`` all the same, so the two never read the columns
/// differently.
///
/// ## Missing is said, never filled
///
/// A shift that predates vehicle profiles, or whose economy was typed by hand,
/// recorded no name, and that reads as `Not recorded`: never today's vehicle,
/// never a name inferred from a matching economy. A missing economy or price is
/// absent rather than `0`. A recorded price of zero **is** a fact and is said.
///
/// ## Names are labels, not identities
///
/// Two shifts both naming `Civic` may have been worked in different vehicles
/// that happened to share a name, or one vehicle renamed in between. Nothing
/// here compares, counts or merges names across shifts.
nonisolated struct RecordedShiftVehicle: Equatable, Sendable {
    let vehicleName: String?
    let milesPerGallon: Decimal?
    let gasPricePerGallon: Money?

    init(context: ShiftVehicleContext, gasPricePerGallon: Money?) {
        vehicleName = context.vehicleName
        milesPerGallon = context.milesPerGallon
        self.gasPricePerGallon = gasPricePerGallon
    }

    /// Whether the shift recorded anything at all about its vehicle or fuel.
    var isRecorded: Bool { vehicleName != nil || milesPerGallon != nil || gasPricePerGallon != nil }

    /// The row's value: the recorded name, or the statement that there is none.
    var title: String { vehicleName ?? "Not recorded" }

    /// `"34 MPG · Gas $3.29/gal"`, either half alone, or `nil`. A missing half
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

    /// The whole snapshot as one spoken sentence, units spelled out.
    ///
    /// Says it was recorded with the shift rather than when the shift started:
    /// a finished shift's assumptions can also be entered afterwards, in its
    /// own editor, and the sentence has to be true of both.
    func spokenLabel(locale: Locale = .autoupdatingCurrent) -> String {
        var parts = [vehicleName.map { "Vehicle recorded with this shift: \($0)" }
            ?? "No vehicle recorded for this shift"]
        if let milesPerGallon {
            parts.append("\(MilesPerGallonInput(locale: locale).text(for: milesPerGallon)) miles per gallon")
        }
        if let gasPricePerGallon {
            parts.append("gas \(gasPricePerGallon.formatted(locale: locale)) per gallon")
        }
        return parts.joined(separator: ", ")
    }
}
