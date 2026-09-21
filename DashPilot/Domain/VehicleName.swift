import Foundation

/// Why a name a driver typed for a vehicle could not be recorded.
nonisolated enum VehicleNameError: Error, Equatable {
    /// Nothing, or nothing but whitespace.
    case empty
    /// Longer than ``VehicleName/maximumLength``.
    case tooLong(maximumLength: Int)
}

nonisolated extension VehicleNameError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            "Give the vehicle a name you will recognise, for example 2020 Honda Civic."
        case let .tooLong(maximumLength):
            "Keep the name to \(maximumLength) characters or fewer. It is how you tell your vehicles apart."
        }
    }
}

/// The rule for what a vehicle profile is called.
///
/// ## What a name is for, and what it is not
///
/// One label a driver recognises — *"2020 Honda Civic"*, *"the van"* — so that a
/// list of profiles can be read at a glance and a shift can say which vehicle
/// its fuel estimate describes. It is deliberately **not** an identification of
/// a vehicle: there is no VIN, no plate, no make-and-model lookup, no year
/// field and no registration anywhere in DashPilot, and the length limit is part
/// of what keeps a name from quietly becoming one.
///
/// ## It is not ``PickupPlaceName``
///
/// A pickup place has a normalisation policy because two spellings of one
/// restaurant have to resolve to one place, and that matching is deliberately
/// conservative. Nothing matches vehicles: a profile is a row the driver created
/// and selects by hand, two profiles with the same name are two profiles, and
/// there is no merge, no alias and no duplicate detection. So the whole rule
/// here is that a name is present and short, and trimming is for tidiness rather
/// than for identity.
///
/// ## Privacy
///
/// A vehicle name is free text the driver typed, and it is treated exactly as an
/// expense note and a pickup name are: it stays on the device and it is never
/// logged. It reaches a file only through an export the driver started, and only
/// as the snapshot a shift recorded.
nonisolated enum VehicleName {
    /// The longest name that can be recorded.
    ///
    /// Enough for a year, a make and a model, not enough for a description.
    static let maximumLength = 60

    /// The name to store for what the driver typed.
    ///
    /// Leading and trailing whitespace is trimmed, because it is invisible on
    /// screen, and the length is measured on the trimmed text after normalising
    /// the line breaks a paste can bring in. Unlike an expense note, empty is
    /// **refused** rather than stored as absence: a profile with no name is a row
    /// the driver cannot pick out of a list.
    ///
    /// - Throws: ``VehicleNameError``.
    static func name(from text: String) throws(VehicleNameError) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        // Counted in `Character`s, which is what a driver sees.
        guard trimmed.count <= maximumLength else { throw .tooLong(maximumLength: maximumLength) }
        return trimmed
    }
}
