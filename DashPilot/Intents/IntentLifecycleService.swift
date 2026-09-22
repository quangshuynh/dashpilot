import Foundation
import OSLog
import SwiftData

/// The eight lifecycle actions DashPilot will perform without a screen, and the
/// one rule that is specific to performing them that way.
///
/// ## It owns no lifecycle logic
///
/// Every invariant still lives where it lived before: at most one shift
/// running, no shift ending or pausing over deliveries in progress, no pausing
/// a shift that is already paused, events in order and once each, timestamps
/// clamped rather than refused. This type calls
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

    /// The shift's Live Activity, told to catch up after every successful write.
    ///
    /// An intent can run with no screen at all, so there is nothing else to
    /// notice that a shift was paused from Siri or from a Lock Screen button. It
    /// is asked to **reconcile**, never told what changed: it reads the store
    /// itself, which is what keeps a presentation surface from ever becoming a
    /// second account of what happened.
    ///
    /// Optional because a test points this service at its own store, and a
    /// throwaway store must not drive a real system surface.
    private let activity: (any ShiftActivityReconciling)?

    init(context: ModelContext, activity: (any ShiftActivityReconciling)? = nil) {
        self.context = context
        self.activity = activity
    }

    #if DEBUG
    /// A store that ``forIntent()`` returns instead of the app's own.
    ///
    /// Test seam, and the only way an intent's own `perform()` can be exercised
    /// against a throwaway store: an intent is created by the system with no
    /// arguments, so there is nowhere for a test to hand it a context. Debug
    /// builds only, so a shipped intent has exactly one store it can reach.
    static var testContext: ModelContext?

    /// The Live Activity ``forIntent()`` reconciles while ``testContext`` is set.
    ///
    /// Nothing by default, so a test that only cares about what was written
    /// reaches no system surface at all. Debug builds only.
    static var testActivity: (any ShiftActivityReconciling)?
    #endif

    /// The service an intent performs with, over the process's own container.
    ///
    /// - Throws: ``IntentLifecycleError/storeUnavailable`` if the store cannot
    ///   be opened. Nothing is recorded, and the intent says so rather than
    ///   reporting a success it did not achieve.
    static func forIntent() throws -> IntentLifecycleService {
        #if DEBUG
        if let testContext {
            return IntentLifecycleService(context: testContext, activity: testActivity)
        }
        #endif
        do {
            return IntentLifecycleService(
                context: try AppModelContainer.shared.get().mainContext,
                activity: AppShiftLiveActivity.shared
            )
        } catch {
            AppLog.intents.error("An intent could not open the local store: \(error)")
            throw IntentLifecycleError.storeUnavailable
        }
    }

    /// Brings the Live Activity back into line with the store.
    ///
    /// Called **after** a write and never before one, so a refused transition
    /// leaves the surface saying what the store still holds. A refusal writes
    /// nothing, so there is nothing for the activity to catch up with.
    private func reconcileActivity() {
        activity?.reconcile()
    }

    // MARK: Shift

    /// Starts a shift.
    func startShift(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).startShift(at: date) }
        reconcileActivity()
        AppLog.intents.info("Intent started a shift")
        // The recorded timestamp, not the one that was asked for: the service
        // is free to clamp it, and the confirmation reports what was stored.
        return .shiftStarted(at: shift.startedAt)
    }

    /// Ends the shift in progress.
    ///
    /// Deliberately not confirmed first. The transition that would cost a
    /// driver something, ending over deliveries still running, is refused by
    /// ``ShiftService`` and named in the refusal, and the shift's own record
    /// survives ending it early. A spoken yes/no round trip at a kerb buys
    /// nothing that rule does not already provide.
    func endShift(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).endActiveShift(at: date) }
        reconcileActivity()
        AppLog.intents.info("Intent ended a shift")
        // Working, not elapsed: the confirmation says how long the driver
        // worked, and a shift they paused for an hour did not work that hour.
        return .shiftEnded(duration: shift.completedWorkingDuration)
    }

    /// Pauses the shift in progress.
    ///
    /// Refused, with the count named, while any delivery is still running, by
    /// ``ShiftService``'s own rule rather than by a second one here.
    ///
    /// The confirmation says that route recording has stopped, because there is
    /// no screen to notice it on and a driver who believed the route was still
    /// being kept would lose the difference without being told.
    func pauseShift(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).pauseActiveShift(at: date) }
        reconcileActivity()
        AppLog.intents.info("Intent paused a shift")
        // Read from the shift after the write, at the instant the pause was
        // recorded, so the figure is the working time the store now holds rather
        // than one that keeps growing while Siri speaks.
        let pausedAt = shift.openPause?.startedAt ?? date
        return .shiftPaused(workingDuration: shift.workingDuration(asOf: pausedAt))
    }

    /// Resumes the paused shift.
    ///
    /// The confirmation carries the same caution a spoken start carries, and for
    /// the same reason: a capture session can only be **started** in the
    /// foreground, so a shift resumed by voice with DashPilot behind another app
    /// records no route until it is opened.
    func resumeShift(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).resumeActiveShift(at: date) }
        reconcileActivity()
        AppLog.intents.info("Intent resumed a shift")
        return .shiftResumed(pausedDuration: shift.pausedTime(asOf: date).duration)
    }

    /// Records that the driver has parked and is walking away from the vehicle.
    ///
    /// **A shift operation, not a delivery one.** Whether the vehicle is moving
    /// is a fact about the driver and their vehicle, so this asks for no
    /// delivery, is refused by no count of them, and the ambiguity that
    /// withholds ``recordDeliveryProgress(at:)`` cannot arise. A driver shopping
    /// for one order while carrying another has one vehicle, and it is parked.
    ///
    /// Every refusal is ``ShiftService/parkActiveShift(at:)``'s, carried through
    /// unchanged: no shift running, already parked, and a paused shift, which
    /// records no route either and already has its own reason for the stop.
    /// Nothing here infers **why** the driver parked.
    ///
    /// The confirmation names the two facts the state is easy to confuse, because
    /// a driver who asked for this from a doorway has no screen to check.
    func parkVehicle(at date: Date = .now) throws -> IntentLifecycleOutcome {
        _ = try shiftRefusal { try ShiftService(context: context).parkActiveShift(at: date) }
        reconcileActivity()
        AppLog.intents.info("Intent recorded the vehicle as parked")
        return .vehicleParked
    }

    /// Records that the driver is driving again.
    ///
    /// Closes the open suspension through ``ShiftService``'s own operation, so
    /// capture resumes as a **new** capture session and no distance is ever
    /// measured across the stretch. Nothing here restarts capture and nothing
    /// deletes a position.
    ///
    /// The confirmation carries the caution a spoken resume carries, for the same
    /// reason: a capture session can only be *started* in the foreground, so a
    /// driver who says this with DashPilot behind another app records no route
    /// until they open it.
    func resumeDriving(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let shift = try shiftRefusal { try ShiftService(context: context).resumeDrivingOnActiveShift(at: date) }
        reconcileActivity()
        AppLog.intents.info("Intent recorded the vehicle as driving again")
        // Read from the shift after the write, like every other figure said
        // back here, so the confirmation reports what the store now holds.
        return .drivingResumed(parkedDuration: shift.suspendedTime(asOf: date).duration)
    }

    // MARK: Delivery

    /// Starts a delivery on the running shift, alongside any already running.
    ///
    /// Unambiguous however many are in progress, because it names no existing
    /// record: it creates one.
    func startDelivery(at date: Date = .now) throws -> IntentLifecycleOutcome {
        let delivery = try deliveryRefusal { try DeliveryService(context: context).startDelivery(at: date) }
        reconcileActivity()
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
        // The same rule the shift's Live Activity applies when it decides
        // whether to offer a step control at all. One definition, two surfaces.
        guard let delivery = UnambiguousDelivery.target(among: running) else {
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

        reconcileActivity()
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
