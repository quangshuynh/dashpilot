import Foundation
import OSLog
import SwiftData

/// What recording one Picked Up or Delivered did.
struct DeliveryProgressResult {
    /// The delivery, now at the step.
    let delivery: Delivery
    /// What the driver's `Resume driving after delivery progress` setting did,
    /// including nothing.
    let parked: ParkedProgressOutcome
    /// The step and the driving it resumed, which the app may offer to take
    /// back together; `nil` unless driving was resumed.
    let undoableAction: ParkedProgressAction?
}

/// The driver's Picked Up and Delivered, from every surface, and the one
/// orchestration of what they may do to a parked vehicle.
///
/// ## The one path behind three surfaces
///
/// The delivery card, ``RecordDeliveryProgressIntent`` and the Lock Screen's
/// step control (through ``IntentLifecycleService/recordDeliveryProgress(at:)``)
/// all record these two steps here, so the setting behaves the same whichever
/// surface the driver used, as Park and Resume Driving already do through
/// ``ParkVehicleService``.
///
/// ## What it adds, and the order it adds it in
///
/// 1. The step, through ``DeliveryService``'s own operation, with its refusals,
///    clamping, save and rollback. A pickup recorded here is always
///    ``PickupProvenance/manual``. A refused or failed step throws, and
///    **nothing else happens**: no driving is recorded for a step the store
///    does not hold.
/// 2. Only then, and only with the setting on and the vehicle still parked,
///    ``ParkedStopCompletion`` decides whether the stop is done.
/// 3. If it is, **``ParkVehicleService/resumeDriving(at:)``**, the operation the
///    Resume Driving button runs, at the instant the step was recorded. So the
///    stretch closes exactly as a manual Resume closes it, and the next capture
///    session is new: nothing is measured across the parked stretch, and
///    nothing is subtracted from working time. There is no second resume.
///
/// ## Why it cannot loop and cannot duplicate
///
/// ``ParkVehicleService`` records Resume's own pickups through
/// ``DeliveryService`` directly and never through this type, so a pickup Resume
/// records cannot resume anything. And ``ParkedStopCompletion`` keeps the stop
/// open while any delivery the stretch was chosen for is still at Arrived at
/// Pickup, so Resume has no pickup to record when this calls it: the only
/// event an automatic resume follows is the driver's own, recorded once.
///
/// ## Two saves, in that order, on purpose
///
/// The step is saved, then the vehicle. A resume that fails leaves the step
/// recorded and the vehicle parked, which is a state the driver can see and
/// fix with one tap; the reverse order could record driving for a step the
/// store then refused.
@MainActor
struct DeliveryProgressService {
    private let context: ModelContext
    private let deliveryCommit: (ModelContext) throws -> Void
    /// Resume Driving, as the button runs it. A seam so a test can refuse it
    /// after the step has been saved.
    private let resumeDriving: @MainActor (ModelContext, Date) throws -> ResumeDrivingResult

    init(
        context: ModelContext,
        deliveryCommit: @escaping (ModelContext) throws -> Void = { try $0.save() },
        resumeDriving: @escaping @MainActor (ModelContext, Date) throws -> ResumeDrivingResult = {
            try ParkVehicleService(context: $0).resumeDriving(at: $1)
        }
    ) {
        self.context = context
        self.deliveryCommit = deliveryCommit
        self.resumeDriving = resumeDriving
    }

    private var deliveries: DeliveryService { DeliveryService(context: context, commit: deliveryCommit) }

    // MARK: Recording

    /// Records `step` for `delivery` and, under the driver's setting, resumes
    /// driving if that leaves the parked stop with nothing to do.
    ///
    /// - Throws: whatever the step's ``DeliveryService`` operation throws. A
    ///   resume that fails is **not** thrown: the step was recorded, and the
    ///   outcome says the vehicle is still parked.
    @discardableResult
    func record(_ step: ParkedProgressStep, of delivery: Delivery, at date: Date = .now) throws -> DeliveryProgressResult {
        switch step {
        case .pickedUp: try deliveries.markPickedUp(delivery, at: date, recordedBy: .manual)
        case .delivered: try deliveries.markDelivered(delivery, at: date)
        }

        guard SettingsService(context: context).resumesDrivingAfterDeliveryProgress(),
              let shift = delivery.shift,
              shift.isRouteSuspended,
              let stretch = shift.openRouteSuspension,
              let recordedAt = Self.instant(of: step, on: delivery)
        else {
            return DeliveryProgressResult(delivery: delivery, parked: .notApplicable, undoableAction: nil)
        }

        let numbers = Dictionary(uniqueKeysWithValues: shift.numberedDeliveries.map { ($0.id, $0.number) })
        let parkedFor = Set(stretch.pickupWorkflowDeliveryIDs)
        let completion = ParkedStopCompletion.evaluate(
            stepped: delivery,
            step: step,
            others: shift.deliveries.filter { $0.id != delivery.id },
            parkedFor: { parkedFor.contains($0.id) },
            number: { numbers[$0.id] ?? .max },
            state: \.state,
            sharedStop: { $0.sharedStopID($1) }
        )
        let name: ([Delivery]) -> [Int] = { $0.compactMap { numbers[$0.id] } }

        switch completion {
        case let .groupedDeliveriesRemain(remaining):
            AppLog.delivery.info("Progress while parked: grouped deliveries remain; the vehicle stays parked")
            return DeliveryProgressResult(
                delivery: delivery, parked: .stillParkedForGroup(step: step, remaining: name(remaining)), undoableAction: nil
            )
        case let .otherDeliveriesRemain(remaining):
            AppLog.delivery.info("Progress while parked: other deliveries remain; the vehicle stays parked")
            return DeliveryProgressResult(
                delivery: delivery,
                parked: .stillParkedForOtherOrders(step: step, remaining: name(remaining)),
                undoableAction: nil
            )
        case let .parkedPickupRemains(remaining):
            AppLog.delivery.info("Progress while parked: a parked pickup remains; the vehicle stays parked")
            return DeliveryProgressResult(
                delivery: delivery, parked: .stillParkedForParkedPickup(remaining: name(remaining)), undoableAction: nil
            )
        case .complete:
            break
        }

        let stopNumbers = Self.stopNumbers(of: delivery, step: step, in: shift, numbers: numbers)
        let resumed: ResumeDrivingResult
        do {
            resumed = try resumeDriving(context, recordedAt)
        } catch {
            AppLog.delivery.notice("Progress while parked completed the stop; driving could not be recorded")
            return DeliveryProgressResult(
                delivery: delivery, parked: .resumeNotRecorded(step: step, deliveryNumbers: stopNumbers), undoableAction: nil
            )
        }
        if !resumed.automatedSteps.isEmpty {
            // Unreachable: the rule keeps the stop open while Resume has a
            // pickup to record. Said loudly rather than trusted.
            AppLog.delivery.fault("An automatic resume recorded a pickup the rule should have prevented")
        }

        AppLog.delivery.info("Progress while parked completed the stop; driving resumed by the driver's setting")
        let action = stretch.endedAt.map {
            ParkedProgressAction(
                step: step,
                deliveryID: delivery.id,
                deliveryNumber: numbers[delivery.id],
                recordedAt: recordedAt,
                suspensionID: stretch.id,
                resumedAt: $0
            )
        }
        return DeliveryProgressResult(
            delivery: delivery,
            parked: .resumed(step: step, deliveryNumbers: stopNumbers),
            // Only where a resume also wrote no pickup, which is always; the
            // condition keeps an Undo from ever offering less than it took.
            undoableAction: resumed.automatedSteps.isEmpty ? action : nil
        )
    }

    // MARK: Taking it back

    /// Takes back a step recorded while parked **and** the driving it resumed,
    /// both or neither, in one save.
    ///
    /// Removes the step's timestamp, reopens the parked stretch it closed, and
    /// deletes the route positions recorded since it closed: they were captured
    /// during what the driver now says was still the parked stretch, which is
    /// exactly what parking exists to keep out of a route. Nothing else moves:
    /// no other delivery, no other event, no earlier position, no pause.
    ///
    /// The caller stops capture **before** this, so positions still in memory
    /// are written first and are among those deleted, and reconciles it after.
    ///
    /// - Throws: ``DeliveryLifecycleError/invalidParkedProgressUndo(_:)`` or
    ///   ``DeliveryLifecycleError/storeUnavailable(underlying:)``.
    @discardableResult
    func undo(_ action: ParkedProgressAction) throws -> DeliveryState {
        guard let delivery = try deliveries.delivery(withID: action.deliveryID), let shift = delivery.shift else {
            AppLog.delivery.notice("Refused to undo progress while parked: the delivery no longer exists")
            throw DeliveryLifecycleError.invalidParkedProgressUndo(.stepNoLongerRecorded)
        }

        let latest = shift.routeSuspensionsInOrder.last
        do {
            // Judged, not applied: nothing is mutated until every half passes.
            _ = try ParkedProgressUndo(
                undoing: action,
                record: DeliveryLifecycleRecord(delivery),
                pickupProvenance: delivery.pickupProvenance,
                shiftIsRunning: shift.isActive && !shift.isPaused,
                latestSuspension: latest.map { ($0.id, $0.endedAt) }
            )
        } catch let refusal as ParkedProgressUndoRefusal {
            AppLog.delivery.notice(
                "Refused to undo progress while parked: \(String(describing: refusal), privacy: .public)"
            )
            throw DeliveryLifecycleError.invalidParkedProgressUndo(refusal)
        }

        let departing: [RouteSample]
        do {
            let shiftKey = shift.persistentModelID
            let boundary = action.resumedAt
            departing = try context.fetch(
                FetchDescriptor<RouteSample>(
                    predicate: #Predicate { $0.shift?.persistentModelID == shiftKey && $0.timestamp >= boundary }
                )
            )
        } catch {
            AppLog.delivery.error("Failed to read the route recorded since driving resumed: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        let restored: DeliveryState
        do {
            restored = try delivery.takeBackParkedProgress(action)
            try shift.reopenRouteSuspension(action.suspensionID, closedAt: action.resumedAt)
        } catch let refusal as ParkedProgressUndoRefusal {
            // Unreachable after the judgement above; discarded rather than trusted.
            context.rollback()
            throw DeliveryLifecycleError.invalidParkedProgressUndo(refusal)
        } catch {
            context.rollback()
            throw DeliveryLifecycleError.invalidParkedProgressUndo(.vehicleStateChanged)
        }
        for sample in departing { context.delete(sample) }

        do {
            try deliveryCommit(context)
        } catch {
            // The step, the closed stretch and every position stay as stored.
            context.rollback()
            AppLog.delivery.error("Failed to persist undoing progress while parked: \(error)")
            throw DeliveryLifecycleError.storeUnavailable(underlying: error)
        }

        // Structural only: which step, which state, how many positions. Never
        // which delivery, never when, never where.
        AppLog.delivery.info(
            """
            Progress while parked undone: \(action.step.rawValue, privacy: .public) back to \
            \(restored.rawValue, privacy: .public); vehicle parked again; \
            \(departing.count, privacy: .public) route positions removed
            """
        )
        return restored
    }

    // MARK: Internals

    private static func instant(of step: ParkedProgressStep, on delivery: Delivery) -> Date? {
        switch step {
        case .pickedUp: delivery.pickedUpAt
        case .delivered: delivery.deliveredAt
        }
    }

    /// The stop's deliveries now past `step`, by number: the stepped one, and
    /// those the driver grouped with it for that kind of stop.
    private static func stopNumbers(
        of delivery: Delivery,
        step: ParkedProgressStep,
        in shift: Shift,
        numbers: [UUID: Int]
    ) -> [Int] {
        let identity = delivery.sharedStopID(step.stopKind)
        let past: (Delivery) -> Bool = switch step {
        case .pickedUp: { $0.state == .pickedUp || $0.state == .delivered }
        case .delivered: { $0.state == .delivered }
        }
        let members = shift.deliveries.filter {
            $0.id == delivery.id || (identity != nil && $0.sharedStopID(step.stopKind) == identity && past($0))
        }
        return members.compactMap { numbers[$0.id] }.sorted()
    }
}
