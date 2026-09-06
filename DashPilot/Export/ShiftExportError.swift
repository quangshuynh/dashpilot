import Foundation

/// Why an export could not be produced.
///
/// Each case is a state the interface has to be able to explain in a sentence a
/// driver can act on. None of them exposes a filesystem path, a container URL or
/// an underlying `NSError` description: those say nothing a driver can use and
/// they name locations on their device.
///
/// A malformed historical row is deliberately **not** a case here. A shift whose
/// route measured nothing, whose amount is missing or whose deliveries describe
/// no usable interval exports those absences as absences — the whole export
/// contract is built to represent them — so there is nothing to fail over and
/// nothing is silently dropped.
nonisolated enum ShiftExportError: Error, Equatable {
    /// The scope holds nothing to export: no completed shift, and no recorded
    /// expense either. Offered rather than an empty file, which is a file a
    /// driver would keep and wonder later what it was meant to contain.
    ///
    /// A scope holding **only** expenses is exported. They are records in their
    /// own right, and a day off with a tank of fuel on it is not an empty day.
    case noCompletedShiftsInScope

    /// A running shift was asked for. Its elapsed time is still growing and it
    /// has no finalised amount, so it is not history yet.
    case shiftNotCompleted

    /// The shift the scope names is no longer in the store.
    case shiftUnavailable

    /// The store could not be read.
    case storeUnavailable

    /// The document could not be turned into text.
    case encodingFailed

    /// The temporary location the file is written to could not be prepared.
    case temporaryLocationUnavailable

    /// The file could not be written.
    case writeFailed
}

nonisolated extension ShiftExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noCompletedShiftsInScope:
            "There are no completed shifts and no recorded expenses to export here."
        case .shiftNotCompleted:
            "A shift that is still in progress cannot be exported. End it first."
        case .shiftUnavailable:
            "That shift is no longer in DashPilot, so there is nothing to export."
        case .storeUnavailable:
            "DashPilot could not read its local data store, so the export was not created."
        case .encodingFailed:
            "DashPilot could not write these records to a file."
        case .temporaryLocationUnavailable, .writeFailed:
            "DashPilot could not save the export file on this device. Free up some space and try again."
        }
    }
}
