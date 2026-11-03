import Foundation
import Observation

/// The one pending end-of-shift confirmation, if any, held in the app process.
///
/// ## Why memory and not the store
///
/// A confirmation is worth a few seconds. Persisting it would let one outlive
/// the moment it describes, and a confirmation that outlived the app being
/// terminated would be an armed End Shift waiting on a Lock Screen. Losing it
/// costs the driver one more tap of End Shift, which is the safe direction.
///
/// ## Why it is safe under repeated and concurrent presses
///
/// Every read and write is on the main actor, and Live Activity intents are
/// performed there, so two presses are always checked one after the other.
/// ``check(_:at:)`` clears the confirmation in the same step that accepts it,
/// so of two presses carrying the same token only the first can ever end a
/// shift; the second finds nothing pending.
@MainActor
@Observable
final class ShiftEndConfirmationStore {
    static let shared = ShiftEndConfirmationStore()

    private(set) var pending: PendingShiftEnd?

    @ObservationIgnored private let makeToken: () -> UUID
    @ObservationIgnored private let schedulesExpiry: Bool
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// - Parameter schedulesExpiry: Whether ``request(for:at:onExpiry:)`` runs
    ///   its handler when the window passes. Tests pass `false` and decide
    ///   expiry by the dates they present.
    init(makeToken: @escaping () -> UUID = UUID.init, schedulesExpiry: Bool = true) {
        self.makeToken = makeToken
        self.schedulesExpiry = schedulesExpiry
    }

    /// Starts a confirmation for `shiftID`, replacing any earlier one.
    ///
    /// A fresh token every time, so a card drawn for an earlier request cannot
    /// confirm this one. `onExpiry` runs once the window has passed, so the card
    /// can return to End Shift without anything having been ended.
    @discardableResult
    func request(for shiftID: UUID, at date: Date, onExpiry: (@MainActor () -> Void)? = nil) -> PendingShiftEnd {
        let request = PendingShiftEnd(shiftID: shiftID, token: makeToken(), requestedAt: date)
        pending = request
        expiryTask?.cancel()
        if schedulesExpiry, let onExpiry {
            expiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(PendingShiftEnd.window))
                guard !Task.isCancelled, let self else { return }
                if self.pending?.token == request.token { self.pending = nil }
                onExpiry()
            }
        }
        return request
    }

    /// The confirmation still valid for `shiftID` at `date`, if any.
    func pending(for shiftID: UUID, at date: Date) -> PendingShiftEnd? {
        guard let pending, pending.shiftID == shiftID, pending.isValid(at: date) else { return nil }
        return pending
    }

    /// Checks a presented confirmation and, if it is accepted, uses it up.
    ///
    /// A stale reference leaves the pending confirmation alone: a press from a
    /// card drawn for an earlier request must not withdraw the newer one.
    func check(_ reference: ShiftActivityEndConfirmation, at date: Date) -> PendingShiftEndCheck {
        guard let pending else { return .expired }
        guard pending.matches(reference) else { return .stale }
        clear()
        return pending.isValid(at: date) ? .confirmed(pending) : .expired
    }

    /// Withdraws the confirmation `reference` names. Returns whether it was the
    /// one pending.
    @discardableResult
    func withdraw(_ reference: ShiftActivityEndConfirmation) -> Bool {
        guard pending?.matches(reference) == true else { return false }
        clear()
        return true
    }

    func clear() {
        pending = nil
        expiryTask?.cancel()
        expiryTask = nil
    }
}
