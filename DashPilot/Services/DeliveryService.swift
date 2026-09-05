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
    /// A delivery was already in progress when a new one was requested.
    case deliveryAlreadyActive(state: DeliveryState)
    /// A transition was requested while no delivery was in progress.
    case noActiveDelivery
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
        case let (.deliveryAlreadyActive(lhsState), .deliveryAlreadyActive(rhsState)): lhsState == rhsState
        case (.noActiveDelivery, .noActiveDelivery): true
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
        case let .deliveryAlreadyActive(state):
            "A delivery is already in progress (\(state.statusDescription.lowercased())). Complete or cancel it first."
        case .noActiveDelivery:
            "There is no delivery in progress."
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
/// ## What it enforces
///
/// - A delivery belongs to exactly one shift, and can only begin while that
///   shift is running.
/// - **At most one delivery is active at a time.** The rule is checked against
///   the store, not against a view's state, so no screen and no future caller
///   can produce a second one.
/// - Transitions happen in lifecycle order, once each, and never after the
///   delivery has finished. The service resolves the active delivery itself and
///   asks the model to apply the event, so there is no API through which an
///   out-of-order transition can be expressed.
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
/// SwiftData is the only source of truth. Nothing here caches "a delivery is
/// running", so a delivery left active when the app was terminated is simply
/// still active when a new service reads the store.
///
/// `@MainActor` isolated, like ``ShiftService``: every operation runs to
/// completion without suspending, so two callers cannot interleave the check
/// for an active delivery with the insert that follows it.
@MainActor
struct DeliveryService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The delivery currently in progress, or `nil` if none is.
    ///
    /// Active means neither delivered nor cancelled, read from the timestamps
    /// themselves. The query is not scoped to the running shift on purpose: the
    /// single-active-delivery rule is about the driver, and a delivery left
    /// active on some other shift must block a new one rather than be hidden by
    /// a narrower fetch.
    ///
    /// - Throws: ``DeliveryLifecycleError/storeUnavailable(underlying:)`` if the store cannot be read.
    func activeDelivery() throws -> Delivery? {
        var descriptor = FetchDescriptor<Delivery>(
            predicate: #Predicate { $0.deliveredAt == nil && $0.cancelledAt == nil },
            sortBy: [SortDescriptor(\.acceptedAt, order: .reverse)]
        )
        // One more than the invariant permits, so a broken store is noticed
        // instead of silently reduced to its first row.
        descriptor.fetchLimit = 2

        let unfinished: [Delivery]
        do {
            unfinished = try context.fetch(descriptor)
        } catch {
            AppLog.delivery.error("Failed to read the active delivery: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        if unfinished.count > 1 {
            // Deterministic and conservative: the most recently accepted one is
            // treated as active, exactly as `ShiftService` treats an extra
            // unfinished shift. Nothing is closed, cancelled or deleted to
            // tidy the store up — the older row is a delivery the driver
            // recorded, and repairing it by guessing an ending would fabricate
            // the one thing this model exists to avoid. It keeps blocking a new
            // delivery until the driver finishes it, which is visible rather
            // than silent.
            AppLog.delivery.fault("Store holds more than one unfinished delivery; treating the most recent as active")
        }
        return unfinished.first
    }

    /// Starts a delivery on the running shift.
    ///
    /// - Throws: ``DeliveryLifecycleError/noActiveShift`` if no shift is
    ///   running, ``DeliveryLifecycleError/deliveryAlreadyActive(state:)`` if one
    ///   is already in progress, or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func startDelivery(at date: Date = .now) throws -> Delivery {
        guard let shift = try activeShift() else {
            AppLog.delivery.notice("Refused to start a delivery: no shift is running")
            throw DeliveryLifecycleError.noActiveShift
        }

        if let running = try activeDelivery() {
            AppLog.delivery.notice("Refused to start a delivery: one is already in progress")
            throw DeliveryLifecycleError.deliveryAlreadyActive(state: running.state)
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

        AppLog.delivery.info("Delivery started")
        return delivery
    }

    /// Records that the driver reached the pickup.
    @discardableResult
    func markArrivedAtPickup(at date: Date = .now) throws -> Delivery {
        try advance(to: .arrivedAtPickup, at: date) { delivery, eventDate in
            try delivery.markArrivedAtPickup(at: eventDate)
        }
    }

    /// Records that the order is in the car.
    @discardableResult
    func markPickedUp(at date: Date = .now) throws -> Delivery {
        try advance(to: .pickedUp, at: date) { delivery, eventDate in
            try delivery.markPickedUp(at: eventDate)
        }
    }

    /// Records that the delivery was completed.
    @discardableResult
    func markDelivered(at date: Date = .now) throws -> Delivery {
        try advance(to: .delivered, at: date) { delivery, eventDate in
            try delivery.markDelivered(at: eventDate)
        }
    }

    /// Records that the active delivery ended without being completed.
    ///
    /// The delivery is kept. A cancelled delivery is history — the driver drove
    /// to a pickup and waited there — and deleting it would remove work that
    /// happened from the shift it happened in.
    @discardableResult
    func cancelActiveDelivery(at date: Date = .now) throws -> Delivery {
        try advance(to: .cancelled, at: date) { delivery, eventDate in
            try delivery.cancel(at: eventDate)
        }
    }

    /// Applies one lifecycle event to the delivery in progress.
    ///
    /// Resolving the delivery here rather than accepting one as a parameter is
    /// what makes the single-active-delivery rule structural: there is no way
    /// to address a finished delivery, or a second active one, through this API.
    ///
    /// - Throws: ``DeliveryLifecycleError/noActiveDelivery``,
    ///   ``DeliveryLifecycleError/invalidTransition(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    private func advance(
        to recorded: DeliveryState,
        at date: Date,
        applying transition: (Delivery, Date) throws -> Void
    ) throws -> Delivery {
        guard let delivery = try activeDelivery() else {
            AppLog.delivery.notice("Refused a delivery transition: none is in progress")
            throw DeliveryLifecycleError.noActiveDelivery
        }

        // The same rule `ShiftService` applies to a shift end: a clock that has
        // moved backwards must not stop a driver recording what just happened,
        // and a clamped event produces a zero-length interval rather than a
        // negative one.
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

        // Structural only: which event, never when it happened, where it
        // happened or what it paid.
        AppLog.delivery.info("Delivery advanced to \(recorded.rawValue, privacy: .public)")
        return delivery
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
