import Foundation
import OSLog
import SwiftData

/// Failures raised when a delivery lifecycle operation cannot be applied.
///
/// Each case carries enough to write a sentence about it, because every one of
/// them is something a driver may see on a running shift.
nonisolated enum DeliveryLifecycleError: Error {
    /// A delivery was requested while no shift was running.
    case noActiveShift
    /// A transition was requested for a delivery that is not attached to a
    /// shift that is still running.
    ///
    /// Unreachable through the ordinary API — a delivery is created on the
    /// running shift, never moved to another, and a shift cannot end while one
    /// of its deliveries is active — so this reports a store holding data the
    /// app cannot produce rather than an ordinary refusal.
    case deliveryNotOnARunningShift
    /// The delivery model rejected the transition.
    case invalidTransition(DeliveryError)
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension DeliveryLifecycleError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.noActiveShift, .noActiveShift): true
        case (.deliveryNotOnARunningShift, .deliveryNotOnARunningShift): true
        case let (.invalidTransition(lhsError), .invalidTransition(rhsError)): lhsError == rhsError
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension DeliveryLifecycleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noActiveShift:
            "Start a shift before recording a delivery."
        case .deliveryNotOnARunningShift:
            "That delivery belongs to a shift that has already ended, so it cannot be changed."
        case .invalidTransition(.alreadyFinished(.delivered)):
            "That delivery is already recorded as delivered."
        case .invalidTransition(.alreadyFinished(.cancelled)):
            "That delivery was cancelled and cannot be continued."
        case .invalidTransition(.alreadyFinished):
            "That delivery has finished and cannot be changed."
        case let .invalidTransition(.alreadyRecorded(state)):
            "\(state.historyDescription) is already recorded for this delivery."
        case let .invalidTransition(.outOfOrder(missing)):
            "Record \(missing.historyDescription.lowercased()) first."
        case .invalidTransition(.timestampPrecedesLastEvent):
            "That would record a delivery event before one that already happened."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the delivery was not changed."
        }
    }
}

/// The delivery lifecycle: starting one, moving it through the events a driver
/// can truthfully record, and ending it either delivered or cancelled.
///
/// ## Several deliveries at once
///
/// A driver can be working more than one order at a time, so **any number of
/// deliveries may be active**, and each one advances on its own. That is the
/// whole reason every mutation here takes the delivery it applies to as a
/// parameter: with two active, "the active delivery" is not a thing the service
/// could resolve, and resolving one anyway — the newest, the oldest, the first
/// row a fetch returned — would attach a driver's tap to a record they did not
/// mean. There is no API here that guesses.
///
/// ## What it enforces
///
/// - A delivery belongs to exactly one shift, and can only begin while that
///   shift is running.
/// - A lifecycle event is applied to **exactly one delivery, named by the
///   caller**, and never to another. Nothing is shared between concurrent
///   deliveries: starting, advancing, finishing or cancelling one leaves every
///   other one exactly as it was.
/// - A delivery can only be advanced while the shift it belongs to is still
///   running.
/// - Transitions happen in lifecycle order, once each, and never after the
///   delivery has finished. Those rules live on ``Delivery`` itself, so they
///   hold for every caller.
///
/// ## Timestamps
///
/// Every operation takes its date, so tests are deterministic and nothing in
/// the model reaches for `Date()`. A date behind the last recorded event is
/// clamped forward rather than refused, which is the rule ``ShiftService``
/// already applies when the device clock moves behind a shift's start: a driver
/// must always be able to record what just happened, and a clamped event
/// records a zero-length interval instead of a negative one.
///
/// SwiftData is the only source of truth. Nothing here caches which deliveries
/// are running, so deliveries left active when the app was terminated are
/// simply still active — all of them, with their own timestamps — when a new
/// service reads the store.
///
/// `@MainActor` isolated, like ``ShiftService``: every operation runs to
/// completion without suspending, so two callers cannot interleave a read with
/// the write that follows it.
@MainActor
struct DeliveryService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Every delivery in the store that is neither delivered nor cancelled, in
    /// deterministic order.
    ///
    /// Active is read from the timestamps themselves rather than from a stored
    /// flag. More than one is expected: it is what stacked delivery work looks
    /// like, and it is no longer treated as a damaged store.
    ///
    /// The result is ordered by ``Delivery/acceptedBefore(_:_:)`` rather than by
    /// whatever order the fetch produced, so presentation and recovery see the
    /// same sequence every time.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the store cannot be read.
    func activeDeliveries() throws -> [Delivery] {
        let descriptor = FetchDescriptor<Delivery>(
            predicate: #Predicate { $0.deliveredAt == nil && $0.cancelledAt == nil },
            sortBy: [SortDescriptor(\.acceptedAt)]
        )

        let unfinished: [Delivery]
        do {
            unfinished = try context.fetch(descriptor)
        } catch {
            AppLog.delivery.error("Failed to read active deliveries: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        let ordered = unfinished.sorted(by: Delivery.acceptedBefore)

        // What *cannot* legitimately exist is an active delivery attached to a
        // shift that has already ended, or to no shift at all: a delivery is
        // created on the running shift, never reparented, and a shift cannot end
        // while any of its deliveries are active. Such a row is reported and
        // left alone — nothing is closed, cancelled, deleted or reparented to
        // tidy it up, because every one of those would invent a fact about work
        // the driver did.
        let stranded = ordered.filter { $0.shift?.isActive != true }
        if !stranded.isEmpty {
            AppLog.delivery.fault(
                "Store holds \(stranded.count, privacy: .public) active deliveries not attached to a running shift"
            )
        }

        return ordered
    }

    /// The deliveries `shift` still has running, in the same deterministic order.
    ///
    /// This is the query the running-shift interface and relaunch recovery are
    /// built from. It is a query, not a mutation seam: nothing is advanced,
    /// finished or repaired by reading it.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the store cannot be read.
    func activeDeliveries(for shift: Shift) throws -> [Delivery] {
        let shiftID = shift.id
        return try activeDeliveries().filter { $0.shift?.id == shiftID }
    }

    /// Starts a delivery on the running shift, alongside any already in progress.
    ///
    /// Nothing already recorded is touched. There is deliberately no maximum:
    /// how many orders a driver is carrying is a fact about their work, not a
    /// number this app is in a position to cap.
    ///
    /// - Throws: ``DeliveryLifecycleError/noActiveShift`` if no shift is
    ///   running, or ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func startDelivery(at date: Date = .now) throws -> Delivery {
        guard let shift = try activeShift() else {
            AppLog.delivery.notice("Refused to start a delivery: no shift is running")
            throw DeliveryLifecycleError.noActiveShift
        }

        // A delivery cannot have been accepted before the shift it belongs to
        // began. Clamping rather than refusing keeps the driver able to record
        // the delivery, and records a delivery that starts with its shift.
        let acceptedAt = max(date, shift.startedAt)
        if acceptedAt != date {
            AppLog.delivery.warning("Delivery start preceded the shift start; clamped to the shift start")
        }

        let delivery = Delivery(shift: shift, acceptedAt: acceptedAt)
        context.insert(delivery)
        do {
            try context.save()
        } catch {
            // Leave nothing half-started in memory that the store does not hold.
            context.rollback()
            AppLog.delivery.error("Failed to persist a delivery start: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // A count, which is structural. Not when it started, and not which one.
        AppLog.delivery.info(
            "Delivery started; \(shift.activeDeliveries.count, privacy: .public) now active on this shift"
        )
        return delivery
    }

    /// Records that the driver reached `delivery`'s pickup.
    @discardableResult
    func markArrivedAtPickup(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .arrivedAtPickup, at: date) { delivery, eventDate in
            try delivery.markArrivedAtPickup(at: eventDate)
        }
    }

    /// Records that `delivery`'s order is in the car.
    @discardableResult
    func markPickedUp(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .pickedUp, at: date) { delivery, eventDate in
            try delivery.markPickedUp(at: eventDate)
        }
    }

    /// Records that `delivery` was completed.
    @discardableResult
    func markDelivered(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .delivered, at: date) { delivery, eventDate in
            try delivery.markDelivered(at: eventDate)
        }
    }

    /// Records that `delivery` ended without being completed.
    ///
    /// One named delivery, never "the delivery in progress". With two orders in
    /// the car, a cancel control that picked its own target would be the most
    /// destructive guess in the app, and the mistake is not undoable.
    ///
    /// The delivery is kept. A cancelled delivery is history — the driver drove
    /// to a pickup and waited there — and deleting it would remove work that
    /// happened from the shift it happened in.
    @discardableResult
    func cancelDelivery(_ delivery: Delivery, at date: Date = .now) throws -> Delivery {
        try advance(delivery, to: .cancelled, at: date) { delivery, eventDate in
            try delivery.cancel(at: eventDate)
        }
    }

    /// Applies one lifecycle event to one named delivery.
    ///
    /// - Throws: ``DeliveryLifecycleError/deliveryNotOnARunningShift``,
    ///   ``DeliveryLifecycleError/invalidTransition(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    private func advance(
        _ delivery: Delivery,
        to recorded: DeliveryState,
        at date: Date,
        applying transition: (Delivery, Date) throws -> Void
    ) throws -> Delivery {
        try validateShift(of: delivery)

        // The same rule `ShiftService` applies to a shift end: a clock that has
        // moved backwards must not stop a driver recording what just happened,
        // and a clamped event produces a zero-length interval rather than a
        // negative one. It is read from *this* delivery's own last event, so a
        // second delivery's timeline has no influence on it.
        let eventDate = max(date, delivery.lastEventAt)
        if eventDate != date {
            AppLog.delivery.warning("Delivery event preceded the previous one; clamped to the previous event")
        }

        do {
            try transition(delivery, eventDate)
        } catch let error as DeliveryError {
            AppLog.delivery.notice("Delivery rejected a transition: \(String(describing: error), privacy: .public)")
            throw DeliveryLifecycleError.invalidTransition(error)
        }

        do {
            try context.save()
        } catch {
            // Discards the pending timestamp: the model must not claim an event
            // the store does not record.
            context.rollback()
            AppLog.delivery.error("Failed to persist a delivery transition: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only: which event, never which delivery, when it happened,
        // where it happened or what it paid.
        AppLog.delivery.info("Delivery advanced to \(recorded.rawValue, privacy: .public)")
        return delivery
    }

    /// Refuses to change a delivery that is not attached to a running shift.
    ///
    /// Through the ordinary API this cannot happen. It is checked anyway,
    /// because a store that somehow holds an active delivery on a finished shift
    /// — or on no shift at all — holds data the app cannot produce, and writing
    /// further lifecycle events into it would turn a structural fault into a
    /// longer and more confusing history. The row is left exactly as it is and
    /// the fault is logged; nothing is reparented, closed or deleted.
    private func validateShift(of delivery: Delivery) throws {
        guard let shift = delivery.shift else {
            AppLog.delivery.fault("Refused a transition: the delivery is attached to no shift")
            throw DeliveryLifecycleError.deliveryNotOnARunningShift
        }
        guard shift.isActive else {
            AppLog.delivery.fault("Refused a transition: the delivery's shift has already ended")
            throw DeliveryLifecycleError.deliveryNotOnARunningShift
        }
    }

    /// The running shift, read through ``ShiftService`` so there is one
    /// definition of "the active shift" — including how an anomalous store with
    /// more than one unfinished shift is handled.
    private func activeShift() throws -> Shift? {
        do {
            return try ShiftService(context: context).activeShift()
        } catch let ShiftLifecycleError.storeUnavailable(underlying) {
            throw DeliveryLifecycleError.storeUnavailable(underlying: underlying)
        }
    }
}
