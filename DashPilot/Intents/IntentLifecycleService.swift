import Foundation
import OSLog
import SwiftData

/// The four lifecycle actions DashPilot will perform without a screen, and the
/// one rule that is specific to performing them that way.
///
/// ## It owns no lifecycle logic
///
/// Every invariant still lives where it lived before: at most one shift
/// running, no shift ending over deliveries in progress, events in order and
/// once each, timestamps clamped rather than refused. This type calls
/// ``ShiftService`` and ``DeliveryService`` and adds nothing to them. If a rule
/// here disagreed with the app, the app would be right, so there is no rule
/// here to disagree with.
///
/// ## What it does own: which delivery a spoken sentence meant
///
/// A driver can be carrying several orders, and a voice surface has no card to
/// tap. "Record the next step" therefore identifies a delivery only while
/// exactly one is running; with two, the request is refused rather than
/// resolved by a guess. That is the same principle ``DeliveryService`` holds by
/// taking its delivery as a parameter, applied where there is nobody to supply
/// one.
///
/// ## What it will not do
///
/// No cancellation, no earnings, no expense, no pickup name, no location. A
/// cancellation cannot be undone and, spoken, could not be aimed; the rest are
/// figures and names that belong to a keyboard and a screen the driver is
/// looking at, not to a sentence said at a junction.
///
/// `@MainActor` isolated, like the services it calls, and every operation runs
/// to completion without suspending.
@MainActor
struct IntentLifecycleService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    #if DEBUG
    /// A store that ``forIntent()`` returns instead of the app's own.
    ///
    /// Test seam, and the only way an intent's own `perform()` can be exercised
    /// against a throwaway store: an intent is created by the system with no
    /// arguments, so there is nowhere for a test to hand it a context. Debug
    /// builds only, so a shipped intent has exactly one store it can reach.
    static var testContext: ModelContext?
    #endif

    /// The service an intent performs with, over the process's own container.
    ///
    /// - Throws: ``IntentLifecycleError/storeUnavailable`` if the store cannot
    ///   be opened. Nothing is recorded, and the intent says so rather than
    ///   reporting a success it did not achieve.
    static func forIntent() throws -> IntentLifecycleService {
        #if DEBUG
        if let testContext { return IntentLifecycleService(context: testContext) }
        #endif
        do {
            return IntentLifecycleService(context: try AppModelContainer.shared.get().mainContext)
        } catch {
            AppLog.intents.error("An intent could not open the local store: \(error)")
            throw IntentLifecycleError.storeUnavailable
        }
    }

    // MARK: Shift

    /// Starts a shift.
    func startShift(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).startShift(at: date) }
        AppLog.intents.info("Intent started a shift")
        // The recorded timestamp, not the one that was asked for: the service
        // is free to clamp it, and the confirmation reports what was stored.
        return .shiftStarted(at: shift.startedAt)
    }

    /// Ends the shift in progress.
    ///
    /// Deliberately not confirmed first. The transition that would cost a
    /// driver something — ending over deliveries still running — is refused by
    /// ``ShiftService`` and named in the refusal, and the shift's own record
    /// survives ending it early. A spoken yes/no round trip at a kerb buys
    /// nothing that rule does not already provide.
    func endShift(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).endActiveShift(at: date) }
        AppLog.intents.info("Intent ended a shift")
        return .shiftEnded(duration: shift.completedDuration)
    }

    // MARK: Delivery

    /// Starts a delivery on the running shift, alongside any already running.
    ///
    /// Unambiguous however many are in progress, because it names no existing
    /// record: it creates one.
    func startDelivery(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let delivery = try deliveryRefusal { try DeliveryService(context: context).startDelivery(at: date) }
        AppLog.intents.info("Intent started a delivery")
        return .deliveryStarted(
            number: number(of: delivery),
            inProgress: delivery.shift?.activeDeliveries.count
        )
    }

    /// Records the next event of the one delivery in progress.
    ///
    /// - Throws: ``IntentLifecycleError/noDeliveryInProgress`` when nothing is
    ///   running, ``IntentLifecycleError/severalDeliveriesInProgress(count:)``
    ///   when the request names no particular delivery, or whichever refusal
    ///   the services raise.
    func recordDeliveryProgress(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let service = DeliveryService(context: context)

        guard let shift = try shiftRefusal({ try ShiftService(context: context).activeShift() }) else {
            // The same refusal the app gives for a delivery event with no shift
            // running, rather than a second sentence saying the same thing.
            throw IntentLifecycleError.delivery(.noActiveShift)
        }

        let running = try deliveryRefusal { try service.activeDeliveries(for: shift) }
        guard running.count == 1, let delivery = running.first else {
            AppLog.intents.notice(
                "Refused a delivery event: \(running.count, privacy: .public) deliveries in progress"
            )
            throw running.isEmpty
                ? IntentLifecycleError.noDeliveryInProgress
                : IntentLifecycleError.severalDeliveriesInProgress(count: running.count)
        }

        // Which step comes next is ``DeliveryState``'s answer, exactly as it is
        // for the button on the running shift. Nothing here decides the order.
        switch delivery.state.nextAction {
        case .arriveAtPickup:
            try deliveryRefusal { try service.markArrivedAtPickup(delivery, at: date) }
        case .pickUp:
            try deliveryRefusal { try service.markPickedUp(delivery, at: date) }
        case .complete:
            try deliveryRefusal { try service.markDelivered(delivery, at: date) }
        case .start, nil:
            // Unreachable: a delivery that is running always has a next step,
            // and `.start` is never one of them.
            AppLog.intents.fault("A delivery in progress offered no next step")
            throw IntentLifecycleError.noDeliveryInProgress
        }

        AppLog.intents.info("Intent recorded a delivery event")
        // Read back from the delivery rather than from what was asked for, so
        // the confirmation cannot name an event the store did not record.
        return .deliveryEventRecorded(number: number(of: delivery), state: delivery.state)
    }

    // MARK: Internals

    /// What the interface would call this delivery, or `nil` if its shift
    /// cannot be read. Nothing is invented: an unnumbered delivery is confirmed
    /// as "Delivery".
    private func number(of delivery: Delivery) -> Int? {
        delivery.shift?.numberedDeliveries.first { $0.id == delivery.id }?.number
    }

    /// Runs a shift operation, carrying its refusal through unchanged.
    ///
    /// An error of any other kind becomes a store failure: this layer has no
    /// second explanation to offer, and a silent success would be worse than an
    /// imprecise sentence.
    private func shiftRefusal<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as ShiftLifecycleError {
            throw IntentLifecycleError.shift(error)
        } catch {
            throw IntentLifecycleError.shift(.storeUnavailable(underlying: error))
        }
    }

    /// The same, for a delivery operation.
    @discardableResult
    private func deliveryRefusal<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as DeliveryLifecycleError {
            throw IntentLifecycleError.delivery(error)
        } catch {
            throw IntentLifecycleError.delivery(.storeUnavailable(underlying: error))
        }
    }
}
