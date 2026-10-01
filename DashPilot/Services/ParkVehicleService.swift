import Foundation
import OSLog
import SwiftData

/// What one press of Park recorded.
struct ParkVehicleResult {
    /// The shift, now recorded as parked.
    let shift: Shift
    /// What the pickup workflow did, including that it was not enabled.
    let pickup: ParkPickupOutcome
    /// The events the workflow recorded, which the app may offer to take back
    /// together; empty when it recorded none. More than one only for deliveries
    /// the driver recorded as sharing a pickup.
    let automatedSteps: [AutomatedPickupStep]
}

/// What one press of Resume Driving recorded.
struct ResumeDrivingResult {
    /// The shift, now recorded as driving again.
    let shift: Shift
    /// What the pickup workflow did, including that it was not enabled.
    let pickup: ResumePickupOutcome
    /// The events the workflow recorded, which the app may offer to take back
    /// together; empty when it recorded none.
    let automatedSteps: [AutomatedPickupStep]
}

/// Park and Resume Driving, from every surface, in one place.
///
/// ## The one operation behind three surfaces
///
/// The app's buttons, ``ParkVehicleIntent`` and ``ResumeDrivingIntent``, and
/// ``ParkVehicleFromActivityIntent`` and ``ResumeDrivingFromActivityIntent`` all
/// reach ``park(at:)`` and ``resumeDriving(at:)``: the buttons directly, the
/// four intents through ``IntentLifecycleService``. So the driver's pickup
/// workflow applies the same way whichever surface they pressed, and there is no
/// second place it could drift from.
///
/// ## The workflow
///
/// With `Pick up orders with Park & Resume` on:
///
/// - **Park** records the vehicle as parked, then records **Arrived at Pickup**
///   for the delivery ``ParkPickupSelection`` names, unless it already has one.
/// - **Resume Driving** records the vehicle as driving, then records **Picked
///   Up** for **that same delivery**, if it is still at Arrived at Pickup.
///
/// Resume never chooses again. The delivery Park chose is stored on the parked
/// stretch, because Resume is often pressed from the Lock Screen in a process
/// that is not the one that parked, and because choosing again could pick up a
/// different stacked order after the first was cancelled or corrected inside.
///
/// ## A pickup the driver said is shared
///
/// When the chosen delivery was recorded as collected at the **same pickup** as
/// others (``SharedStopKind/pickup``), Park chooses those still waiting for it
/// too, stores **all** of them on the stretch, and records their arrivals in
/// one write; Resume records the pickups of exactly those, in one write. A
/// shared **drop-off** plays no part: two orders for one customer can come from
/// two restaurants, and parking at the first must not record anything for the
/// second. Each shared event is all or nothing, so one press can never leave a
/// shared arrival or a shared pickup half-recorded.
///
/// ## It owns no lifecycle logic
///
/// It **composes** writes that already exist and adds only the decisions
/// between them. Parking and driving are ``ShiftService``'s, unchanged, and
/// still the only things that open or close a ``RouteSuspension``. Arrived at
/// Pickup and Picked Up are ``DeliveryService``'s
/// ``DeliveryService/markArrivedAtPickup(_:at:)`` and
/// ``DeliveryService/markPickedUp(_:at:recordedBy:)``, the operations the
/// delivery's card calls, with the same refusals, the same clamping to the
/// delivery's own last event, and the same save and rollback. The one
/// difference is that a pickup recorded here says
/// ``PickupProvenance/resumeAutomation``.
///
/// ## Two saves each, in that order, on purpose
///
/// **Park**: one save for the vehicle (the suspension and the delivery it is
/// for, together), then one for the arrival. **Resume**: one save for the
/// vehicle, then one for the pickup. The vehicle is always saved first, so a
/// delivery step that is refused or fails can never undo parking or driving:
/// Park must always be able to stop the route and Resume must always be able to
/// restart it. The reverse cannot happen, because no delivery step is attempted
/// without a saved vehicle state. A Park whose arrival failed leaves a stretch
/// associated with a delivery still at Accepted, and Resume then records
/// nothing for it, because it only ever picks up a delivery at Arrived at
/// Pickup.
///
/// ## Timestamps
///
/// Each event is recorded at the instant the vehicle state was recorded at, as
/// stored, through the card's own clamping. Nothing earlier is manufactured and
/// nothing later is guessed: DashPilot does not know when the driver reached the
/// counter or when the order was handed over, and the events record what the
/// driver said by pressing Park and Resume Driving.
@MainActor
struct ParkVehicleService {
    private let context: ModelContext

    /// How a delivery step is handed to the store. The delivery service's own
    /// seam, passed through so a test can refuse the step's save after the
    /// vehicle state has already been saved.
    private let deliveryCommit: (ModelContext) throws -> Void

    init(context: ModelContext, deliveryCommit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.deliveryCommit = deliveryCommit
    }

    private var deliveries: DeliveryService { DeliveryService(context: context, commit: deliveryCommit) }

    // MARK: Park

    /// Records the vehicle as parked and, under the pickup workflow, the chosen
    /// delivery's arrival at its pickup.
    ///
    /// - Throws: whatever ``ShiftService/parkActiveShift(at:pickupWorkflowDeliveryID:)``
    ///   throws. A refused or failed arrival is **not** thrown: parking has
    ///   succeeded, and the outcome says what happened to the arrival.
    @discardableResult
    func park(at date: Date = .now) throws -> ParkVehicleResult {
        let preferences = SettingsService(context: context).pickupWorkflowPreferences()
        guard preferences.usesParkAndResume else {
            let shift = try ShiftService(context: context).parkActiveShift(at: date)
            return ParkVehicleResult(shift: shift, pickup: .notEnabled, automatedSteps: [])
        }

        // Chosen before parking, so the choice is saved with the stretch in the
        // one write that opens it. Reading is all this does: a failure here
        // parks the vehicle with no delivery chosen rather than refusing Park.
        let choice = chooseDeliveries(handlesStackedOrdersInOrder: preferences.handlesStackedOrdersInOrder)
        let targets: [Delivery] = if case let .chosen(deliveries) = choice { deliveries } else { [] }

        let shift = try ShiftService(context: context).parkActiveShift(
            at: date,
            pickupWorkflowDeliveryID: targets.first?.id,
            sharingPickupWith: targets.dropFirst().map(\.id)
        )

        switch choice {
        case .unreadable:
            return ParkVehicleResult(shift: shift, pickup: .deliveriesUnreadable, automatedSteps: [])
        case .none:
            AppLog.delivery.info("Park pickup workflow found no delivery waiting for its pickup")
            return ParkVehicleResult(shift: shift, pickup: .noneAwaitingPickup, automatedSteps: [])
        case let .stackedNotHandled(count):
            // A count is structural. Which deliveries, never.
            AppLog.delivery.notice(
                "Park pickup workflow skipped: \(count, privacy: .public) deliveries in progress, stacked orders off"
            )
            return ParkVehicleResult(shift: shift, pickup: .stackedNotHandled(inProgress: count), automatedSteps: [])
        case let .chosen(deliveries):
            let parkedAt = shift.openRouteSuspension?.startedAt ?? date
            if deliveries.count == 1, let delivery = deliveries.first {
                return recordArrival(of: delivery, on: shift, at: parkedAt)
            }
            return recordSharedArrival(of: deliveries, on: shift, at: parkedAt)
        }
    }

    private enum Choice {
        /// One delivery, or several the driver recorded as sharing its pickup,
        /// lowest number first.
        case chosen([Delivery])
        case stackedNotHandled(Int)
        case none
        case unreadable
    }

    /// The deliveries this Park is for, read from the store and never written.
    private func chooseDeliveries(handlesStackedOrdersInOrder: Bool) -> Choice {
        let numbered: [NumberedDelivery]
        do {
            guard let shift = try ShiftService(context: context).activeShift() else {
                // Park is about to refuse for the same reason, with its own
                // sentence.
                return .none
            }
            let running = Set(try deliveries.activeDeliveries(for: shift).map(\.id))
            numbered = shift.numberedDeliveries.filter { running.contains($0.id) }
        } catch {
            AppLog.delivery.error("Park pickup workflow could not read the deliveries in progress")
            return .unreadable
        }

        switch ParkPickupSelection.select(
            among: numbered,
            handlesStackedOrdersInOrder: handlesStackedOrdersInOrder,
            number: \.number,
            state: \.delivery.state,
            // The shared **pickup** and nothing else: see `SharedStopKind`.
            sharedPickup: \.delivery.sharedPickupID
        ) {
        case let .target(chosen): return .chosen([chosen.delivery])
        case let .sharedPickup(chosen): return .chosen(chosen.map(\.delivery))
        case let .stackedNotHandled(count): return .stackedNotHandled(count)
        case .noneAwaitingPickup: return .none
        }
    }

    private func recordArrival(of delivery: Delivery, on shift: Shift, at date: Date) -> ParkVehicleResult {
        let number = Self.number(of: delivery, in: shift)

        guard delivery.state == .accepted else {
            // Already at Arrived at Pickup: no second event is written, and
            // Resume Driving will record its pickup.
            AppLog.delivery.info("Park pickup workflow chose a delivery already at its pickup")
            return ParkVehicleResult(shift: shift, pickup: .alreadyArrived(deliveryNumber: number), automatedSteps: [])
        }

        do {
            try deliveries.markArrivedAtPickup(delivery, at: date)
        } catch {
            // The service has already rolled back its own pending timestamp. The
            // suspension was saved before this was tried, so the vehicle stays
            // parked.
            AppLog.delivery.notice("Park pickup workflow could not record the arrival; the vehicle stays parked")
            return ParkVehicleResult(shift: shift, pickup: .arrivalNotRecorded(deliveryNumber: number), automatedSteps: [])
        }

        AppLog.delivery.info("Park pickup workflow recorded an arrival")
        let steps = delivery.arrivedAtPickupAt.map {
            [AutomatedPickupStep(kind: .arrivedWhenParked, deliveryID: delivery.id, deliveryNumber: number, recordedAt: $0)]
        } ?? []
        return ParkVehicleResult(shift: shift, pickup: .markedArrived(deliveryNumber: number), automatedSteps: steps)
    }

    /// Records Arrived at Pickup, together, for the chosen deliveries sharing
    /// one pickup that do not have it yet.
    private func recordSharedArrival(of chosen: [Delivery], on shift: Shift, at date: Date) -> ParkVehicleResult {
        let numbers = Self.numbers(in: shift)
        let arriving = chosen.filter { $0.state == .accepted }
        let alreadyThere = chosen.filter { $0.state != .accepted }
        let arrival = SharedPickupArrival(
            recorded: arriving.compactMap { numbers[$0.id] },
            alreadyArrived: alreadyThere.compactMap { numbers[$0.id] }
        )

        guard !arriving.isEmpty else {
            AppLog.delivery.info("Park pickup workflow chose a shared pickup already arrived at")
            return ParkVehicleResult(shift: shift, pickup: .sharedPickupArrived(arrival), automatedSteps: [])
        }

        do {
            try deliveries.markArrivedAtPickup(together: arriving, at: date)
        } catch {
            // Rolled back whole by the service: none of them was recorded, and
            // the suspension saved before this stands.
            AppLog.delivery.notice(
                "Park pickup workflow could not record a shared arrival; none was recorded and the vehicle stays parked"
            )
            return ParkVehicleResult(
                shift: shift,
                pickup: .sharedPickupArrivalNotRecorded(deliveryNumbers: arrival.recorded),
                automatedSteps: []
            )
        }

        AppLog.delivery.info(
            "Park pickup workflow recorded \(arriving.count, privacy: .public) arrivals at a shared pickup"
        )
        let steps = arriving.compactMap { delivery in
            delivery.arrivedAtPickupAt.map {
                AutomatedPickupStep(
                    kind: .arrivedWhenParked, deliveryID: delivery.id, deliveryNumber: numbers[delivery.id], recordedAt: $0
                )
            }
        }
        return ParkVehicleResult(shift: shift, pickup: .sharedPickupArrived(arrival), automatedSteps: steps)
    }

    // MARK: Resume Driving

    /// Records the vehicle as driving again and, under the pickup workflow, the
    /// pickup of the delivery this parked stretch was for.
    ///
    /// - Throws: whatever ``ShiftService/resumeDrivingOnActiveShift(at:)``
    ///   throws. A refused or failed pickup is **not** thrown: driving has been
    ///   recorded, and the outcome says what happened to the pickup.
    @discardableResult
    func resumeDriving(at date: Date = .now) throws -> ResumeDrivingResult {
        // Read before the write closes it. A read that fails leaves no
        // association, and the resume below reports its own refusal if there is
        // one.
        let stretch = (try? ShiftService(context: context).activeShift())?.openRouteSuspension
        let parkedFor = stretch?.pickupWorkflowDeliveryIDs ?? []

        let shift = try ShiftService(context: context).resumeDrivingOnActiveShift(at: date)

        guard SettingsService(context: context).pickupWorkflowPreferences().usesParkAndResume else {
            return ResumeDrivingResult(shift: shift, pickup: .notEnabled, automatedSteps: [])
        }
        let resumedAt = stretch?.endedAt ?? date
        switch parkedFor.count {
        case 0:
            return ResumeDrivingResult(shift: shift, pickup: .noParkedPickup, automatedSteps: [])
        case 1:
            return recordPickup(ofDeliveryWithID: parkedFor[0], on: shift, at: resumedAt)
        default:
            // Exactly the deliveries Park stored, never the shared pickup as it
            // is grouped now: a correction made while parked changes the next
            // Park, not this one.
            return recordSharedPickup(ofDeliveriesWithIDs: parkedFor, on: shift, at: resumedAt)
        }
    }

    private func recordPickup(ofDeliveryWithID id: UUID, on shift: Shift, at date: Date) -> ResumeDrivingResult {
        let delivery: Delivery?
        do {
            delivery = try deliveries.delivery(withID: id)
        } catch {
            AppLog.delivery.error("Resume pickup workflow could not read the delivery it parked for")
            return ResumeDrivingResult(shift: shift, pickup: .pickupNotRecorded(deliveryNumber: nil), automatedSteps: [])
        }

        // Only a delivery of this shift. An identifier that resolves elsewhere
        // is a store the app did not write, and is treated as gone.
        guard let delivery, delivery.shift?.id == shift.id else {
            AppLog.delivery.notice("Resume pickup workflow: the delivery it parked for no longer exists")
            return ResumeDrivingResult(shift: shift, pickup: .noLongerInProgress(deliveryNumber: nil), automatedSteps: [])
        }
        let number = Self.number(of: delivery, in: shift)

        switch delivery.state {
        case .arrivedAtPickup:
            break
        case .pickedUp:
            return ResumeDrivingResult(shift: shift, pickup: .alreadyPickedUp(deliveryNumber: number), automatedSteps: [])
        case .accepted:
            AppLog.delivery.notice("Resume pickup workflow: the delivery it parked for has no arrival recorded")
            return ResumeDrivingResult(shift: shift, pickup: .notAtPickup(deliveryNumber: number), automatedSteps: [])
        case .delivered, .cancelled:
            AppLog.delivery.notice("Resume pickup workflow: the delivery it parked for has finished")
            return ResumeDrivingResult(shift: shift, pickup: .noLongerInProgress(deliveryNumber: number), automatedSteps: [])
        }

        do {
            try deliveries.markPickedUp(delivery, at: date, recordedBy: .resumeAutomation)
        } catch {
            // Rolled back by the service. Driving was saved first and stands.
            AppLog.delivery.notice("Resume pickup workflow could not record the pickup; the vehicle is driving")
            return ResumeDrivingResult(shift: shift, pickup: .pickupNotRecorded(deliveryNumber: number), automatedSteps: [])
        }

        let steps = delivery.pickedUpAt.map {
            [AutomatedPickupStep(kind: .pickedUpWhenResumed, deliveryID: delivery.id, deliveryNumber: number, recordedAt: $0)]
        } ?? []
        return ResumeDrivingResult(shift: shift, pickup: .markedPickedUp(deliveryNumber: number), automatedSteps: steps)
    }

    /// Records Picked Up, together, for the deliveries Park chose at a shared
    /// pickup that are still at Arrived at Pickup, and names the rest.
    private func recordSharedPickup(ofDeliveriesWithIDs ids: [UUID], on shift: Shift, at date: Date) -> ResumeDrivingResult {
        let numbers = Self.numbers(in: shift)
        var eligible: [Delivery] = []
        var alreadyPickedUp: [Int] = []
        var notAtPickup: [Int] = []
        var noLongerInProgress: [Int] = []

        for id in ids {
            let resolved: Delivery?
            do {
                resolved = try deliveries.delivery(withID: id)
            } catch {
                AppLog.delivery.error("Resume pickup workflow could not read the deliveries it parked for")
                return ResumeDrivingResult(
                    shift: shift, pickup: .sharedPickupNotRecorded(deliveryNumbers: []), automatedSteps: []
                )
            }
            // Only a delivery of this shift, as for one delivery. A number it
            // cannot be given is left unnamed rather than invented.
            guard let delivery = resolved, delivery.shift?.id == shift.id else { continue }
            let number = numbers[delivery.id]
            switch delivery.state {
            case .arrivedAtPickup: eligible.append(delivery)
            case .pickedUp: number.map { alreadyPickedUp.append($0) }
            case .accepted: number.map { notAtPickup.append($0) }
            case .delivered, .cancelled: number.map { noLongerInProgress.append($0) }
            }
        }

        let recordedNumbers = eligible.compactMap { numbers[$0.id] }
        let resume = SharedPickupResume(
            recorded: recordedNumbers,
            alreadyPickedUp: alreadyPickedUp,
            notAtPickup: notAtPickup,
            noLongerInProgress: noLongerInProgress
        )
        guard !eligible.isEmpty else {
            AppLog.delivery.notice("Resume pickup workflow: no delivery it parked for is still at its pickup")
            return ResumeDrivingResult(shift: shift, pickup: .sharedPickupPickedUp(resume), automatedSteps: [])
        }

        do {
            try deliveries.markPickedUp(together: eligible, at: date, recordedBy: .resumeAutomation)
        } catch {
            // Rolled back whole by the service. Driving was saved first and
            // stands; none of the pickups was recorded.
            AppLog.delivery.notice(
                "Resume pickup workflow could not record a shared pickup; none was recorded and the vehicle is driving"
            )
            return ResumeDrivingResult(
                shift: shift, pickup: .sharedPickupNotRecorded(deliveryNumbers: recordedNumbers), automatedSteps: []
            )
        }

        let steps = eligible.compactMap { delivery in
            delivery.pickedUpAt.map {
                AutomatedPickupStep(
                    kind: .pickedUpWhenResumed, deliveryID: delivery.id, deliveryNumber: numbers[delivery.id], recordedAt: $0
                )
            }
        }
        return ResumeDrivingResult(shift: shift, pickup: .sharedPickupPickedUp(resume), automatedSteps: steps)
    }

    // MARK: Internals

    /// The number the delivery's card shows, or `nil` when its shift cannot say.
    private static func number(of delivery: Delivery, in shift: Shift) -> Int? {
        shift.numberedDeliveries.first { $0.id == delivery.id }?.number
    }

    /// Every delivery's number in `shift`, by identity, read once.
    private static func numbers(in shift: Shift) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: shift.numberedDeliveries.map { ($0.id, $0.number) })
    }
}
