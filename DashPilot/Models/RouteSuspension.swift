import Foundation
import SwiftData

/// Errors raised when a suspension transition would violate the model's
/// invariants.
nonisolated enum RouteSuspensionError: Error, Equatable {
    /// The suspension already has an end timestamp.
    case alreadyEnded
    /// The proposed end timestamp is earlier than the suspension's start.
    case endPrecedesStart
    /// Reopening was asked of a suspension that is still open.
    case notEnded
    /// Reopening was asked for an end the suspension no longer records.
    case endChanged
}

/// One stretch of a shift the driver recorded the vehicle as parked while they
/// were away from it.
///
/// ## Why this is a row and not a flag
///
/// The same reason ``ShiftPause`` is one. A boolean on `Shift` could say the
/// vehicle is parked now; it could not say for how long, how many times, or
/// when, and a route's coverage has to be able to say all three. An accumulated
/// "suspended seconds" column would be a running sum the app had to keep correct
/// across every crash and failed save, and it is the kind of derived value this
/// project does not persist.
///
/// Rows also mean nothing about the shift's own definitions moves.
/// `Shift.endedAt` is untouched, `endedAt == nil` still means unfinished, and a
/// shift left parked when the app was terminated comes back parked with no
/// recovery code at all, because the row is the only place the state lives.
///
/// ## What it records, and what it must never be read as
///
/// Only when the driver said they had parked and when they said they were
/// driving again. Nothing is observed during one: route capture is stopped for
/// its whole length, so DashPilot does not know whether the vehicle moved, where
/// the driver went or how far they walked, and it never ends one by itself.
///
/// **It is not a pause.** A pause says the driver stopped working and is
/// subtracted from the shift's working duration. Walking into a shop to collect
/// an order is working, so nothing here is ever subtracted from anything: no
/// hourly rate moves, no period figure moves, and a shift that parked twice
/// reports exactly the working duration it would have reported without this.
///
/// The domain reading of these two timestamps lives in
/// ``RouteSuspensionInterval``, which holds the clipping and malformed-row rules
/// and can be tested without a store.
@Model
nonisolated final class RouteSuspension {
    /// Stable identifier, for the reason ``ShiftPause`` has one.
    @Attribute(.unique) private(set) var id: UUID

    private(set) var startedAt: Date

    /// `nil` while the driver has not recorded driving again.
    private(set) var endedAt: Date?

    /// The shift this suspension belongs to.
    ///
    /// **The shift and never a delivery**, which is the decision the whole
    /// feature rests on: whether the vehicle is moving is a fact about the
    /// driver and their vehicle, and a driver shopping for one order while
    /// carrying another has one vehicle and it is parked.
    ///
    /// Optional because SwiftData makes the inverse of a to-many relationship
    /// optional; a suspension with no shift describes a store the app cannot
    /// write.
    private(set) var shift: Shift?

    /// The ``Delivery/id`` this parked stretch was taken to be the pickup of,
    /// under the driver's `Pick up orders with Park & Resume` setting, or `nil`.
    ///
    /// **Written once, by ``ShiftService/parkActiveShift(at:pickupWorkflowDeliveryID:)``,
    /// in the same save that opens the row**, and read once, by
    /// ``ParkVehicleService/resumeDriving(at:)``, which is how Resume Driving
    /// records Picked Up for the delivery Park recorded at its pickup rather than
    /// for whichever delivery a second choice would name. It has to outlive the
    /// process for the reason the row does: Resume is often pressed from the
    /// Lock Screen after iOS has ended the app that parked.
    ///
    /// **An identifier, not a relationship.** The stretch still belongs to the
    /// shift and to no delivery, so however many deliveries are in progress
    /// there is still at most one open row, and nothing cascades either way. An
    /// identifier that no longer resolves, or resolves to a delivery that has
    /// moved on, is read as nothing to pick up.
    ///
    /// `nil` for a stretch parked with the workflow off, for one where no
    /// delivery was waiting for its pickup, and for every stretch recorded
    /// before v19, which migration deliberately did not associate with anything.
    /// It says which delivery the workflow was **for**, never that Park recorded
    /// its arrival: that delivery may already have had one.
    private(set) var pickupWorkflowDeliveryID: UUID?

    /// The **other** deliveries this parked stretch was for, because the driver
    /// recorded them as collected at the same pickup as
    /// ``pickupWorkflowDeliveryID``; empty when there were none.
    ///
    /// Written and read exactly as ``pickupWorkflowDeliveryID`` is, in the same
    /// save that opens the row, and it exists for the same reason: Resume
    /// Driving acts on **exactly** the deliveries Park chose, after a
    /// relaunch, a Lock Screen press or a regrouping in the shop. Reading the
    /// shared pickup again at Resume would let a correction made while parked
    /// pick up an order Park never recorded arriving.
    ///
    /// A separate column rather than a rewrite of the one above, so a stretch
    /// recorded before v20 keeps meaning what it meant: one delivery, and no
    /// others. Identifiers, not relationships, for the same reason as that one.
    /// Empty for every stretch recorded before v20; migration writes nothing.
    private(set) var pickupWorkflowSharedPickupDeliveryIDs: [UUID] = []

    init(
        id: UUID = UUID(),
        shift: Shift,
        startedAt: Date,
        endedAt: Date? = nil,
        pickupWorkflowDeliveryID: UUID? = nil,
        pickupWorkflowSharedPickupDeliveryIDs: [UUID] = []
    ) {
        self.id = id
        self.shift = shift
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pickupWorkflowDeliveryID = pickupWorkflowDeliveryID
        self.pickupWorkflowSharedPickupDeliveryIDs = pickupWorkflowSharedPickupDeliveryIDs
    }

    /// Every delivery this parked stretch was for, the first-numbered first:
    /// the one Park chose and the others sharing its pickup. Empty when it was
    /// for none.
    var pickupWorkflowDeliveryIDs: [UUID] {
        guard let pickupWorkflowDeliveryID else { return [] }
        return [pickupWorkflowDeliveryID] + pickupWorkflowSharedPickupDeliveryIDs
    }

    /// Whether the driver has not recorded driving again.
    var isOpen: Bool { endedAt == nil }

    /// This suspension as the value type the domain reasons about.
    var interval: RouteSuspensionInterval {
        RouteSuspensionInterval(start: startedAt, end: endedAt)
    }

    /// Records that the driver is driving again.
    ///
    /// - Throws: ``RouteSuspensionError`` if it is already ended or `date`
    ///   precedes the start.
    func end(at date: Date) throws {
        guard endedAt == nil else { throw RouteSuspensionError.alreadyEnded }
        guard date >= startedAt else { throw RouteSuspensionError.endPrecedesStart }
        endedAt = date
    }

    /// Takes back the end recorded at `closedAt`: the vehicle never stopped
    /// being parked.
    ///
    /// Only for the Undo of a delivery step that resumed driving
    /// automatically, through ``Shift/reopenRouteSuspension(_:closedAt:)``,
    /// which owns the rules. Refused unless the row is closed at exactly that
    /// instant, so a second invocation writes nothing.
    func reopen(closedAt: Date) throws {
        guard let endedAt else { throw RouteSuspensionError.notEnded }
        guard endedAt == closedAt else { throw RouteSuspensionError.endChanged }
        self.endedAt = nil
    }
}
