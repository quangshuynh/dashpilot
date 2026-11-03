import Foundation
import Observation

/// Which just-ended shift, if any, the app should offer a recap of.
///
/// Held in memory only, like ``ShiftEndConfirmationStore``: a recap is a
/// courtesy for the moment a shift ends, not a record. A shift ended from the
/// Lock Screen while DashPilot is not on screen is offered here the next time
/// the app is in front, if the process is still alive; if it is not, the shift
/// is in History like every other, and nothing claims a recap was pending.
@MainActor
@Observable
final class PostShiftRecapRequests {
    static let shared = PostShiftRecapRequests()

    private(set) var shiftID: UUID?

    /// Called only after an end has been written.
    func post(shiftID: UUID) {
        self.shiftID = shiftID
    }

    func dismiss() {
        shiftID = nil
    }
}

/// One recap to present, identified by its shift.
nonisolated struct PostShiftRecapRequest: Identifiable, Equatable {
    let id: UUID
}
