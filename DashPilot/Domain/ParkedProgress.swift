import Foundation

/// The two delivery steps a driver records that can finish their work at a
/// stop: collecting an order, and handing one over.
nonisolated enum ParkedProgressStep: String, CaseIterable, Hashable, Sendable {
    /// Picked Up: the order is in the car. Finishes work at a **pickup**.
    case pickedUp
    /// Delivered: the order was handed over. Finishes work at a **drop-off**.
    case delivered

    /// The kind of stop this step finishes work at, which is the one shared
    /// stop the rule reads. Never the other: two orders for one customer can
    /// come from two restaurants, and two orders from one restaurant can go to
    /// two customers.
    var stopKind: SharedStopKind {
        switch self {
        case .pickedUp: .pickup
        case .delivered: .dropOff
        }
    }

    /// The state the step records.
    var recordedState: DeliveryState {
        switch self {
        case .pickedUp: .pickedUp
        case .delivered: .delivered
        }
    }

    /// `picked up` or `delivered`, for a sentence.
    var pastTense: String {
        switch self {
        case .pickedUp: "picked up"
        case .delivered: "delivered"
        }
    }

    /// The step a delivery's own next action records, when it is one of these.
    init?(_ action: DeliveryAction?) {
        switch action {
        case .pickUp: self = .pickedUp
        case .complete: self = .delivered
        case .start, .arriveAtPickup, nil: return nil
        }
    }
}

/// Whether the stop a just-recorded Picked Up or Delivered belongs to has
/// anything left to do, while the vehicle is recorded as parked.
///
/// ## What it is for
///
/// The driver's `Resume driving after delivery progress` setting: DashPilot may
/// record driving again when a step the driver recorded while parked leaves
/// **nothing more to record at that stop**. This type decides that, and only
/// that. It never decides that the driver has walked back to the car, and it
/// reads no position, speed, place, address or customer: what it reads is the
/// lifecycle the driver recorded and the shared stops the driver stated.
///
/// ## The stop
///
/// The delivery just stepped, plus every other delivery in progress that the
/// driver recorded as sharing **that kind** of stop with it
/// (``SharedStopKind/pickup`` for Picked Up, ``SharedStopKind/dropOff`` for
/// Delivered, never the other). A grouped member still waiting for that
/// stop's work keeps the stop open: Delivery 4 still to collect at a shared
/// pickup, or still to hand over at a shared drop-off.
///
/// ## Orders the driver did not group are not assumed to be elsewhere
///
/// DashPilot cannot tell two orders from one restaurant from two orders from
/// two restaurants unless the driver said so. So an **ungrouped** order in
/// progress that still needs the same kind of work keeps the vehicle parked
/// too: one still waiting for its pickup, after a Picked Up, or one still in
/// the car, after a Delivered. Completing one of several unrelated orders is
/// never read as having left. An ungrouped order that needs the **other** kind
/// of work does not hold a drop-off open (an order still to collect is not
/// collected at a customer's door), but every order still waiting for its
/// pickup holds a pickup open.
///
/// ## Resume never records a pickup from here
///
/// Resume Driving records Picked Up for the deliveries Park chose for the
/// stretch, when they are still at Arrived at Pickup. A step that resumed
/// driving while one of them was still waiting would have Resume write a
/// pickup the driver never recorded, so any delivery the stretch was for that
/// is still at Arrived at Pickup keeps the stop open. With that, the only
/// event an automatic resume ever follows is the driver's own, and Resume's
/// own pickup step has nothing to do.
///
/// Generic over the element, like ``ParkPickupSelection``: the service
/// resolves a `Delivery`, and the tests resolve plain values.
nonisolated enum ParkedStopCompletion<Element> {
    /// Nothing left to record at the stop: driving may resume.
    case complete
    /// Deliveries the driver grouped with the stepped one still need this
    /// stop's work. Carries them, lowest number first.
    case groupedDeliveriesRemain([Element])
    /// Orders the driver did not group with it still need the same kind of
    /// work, so DashPilot cannot say the stop is over. Carries them, lowest
    /// number first.
    case otherDeliveriesRemain([Element])
    /// A delivery the parked stretch was chosen for is still at Arrived at
    /// Pickup, waiting for Resume Driving to record its pickup.
    case parkedPickupRemains([Element])

    /// The whole rule.
    ///
    /// - Parameters:
    ///   - stepped: the delivery the driver just recorded `step` for, as it is
    ///     now.
    ///   - step: what was recorded.
    ///   - others: every **other** delivery of the shift, in any order and any
    ///     state; finished ones are ignored.
    ///   - parkedFor: whether the open parked stretch was chosen for a
    ///     delivery, by the pickup workflow.
    ///   - number, state, sharedStop: each delivery's number, state and shared
    ///     identity of a kind.
    static func evaluate(
        stepped: Element,
        step: ParkedProgressStep,
        others: [Element],
        parkedFor: (Element) -> Bool,
        number: (Element) -> Int,
        state: (Element) -> DeliveryState,
        sharedStop: (Element, SharedStopKind) -> UUID?
    ) -> Self {
        let inProgress = others.filter { state($0).isActive }.sorted { number($0) < number($1) }
        func awaitingPickup(_ element: Element) -> Bool {
            state(element) == .accepted || state(element) == .arrivedAtPickup
        }
        func needsThisWork(_ element: Element) -> Bool {
            switch step {
            case .pickedUp: awaitingPickup(element)
            // Every delivery still in progress has its handover ahead of it.
            case .delivered: true
            }
        }

        let identity = sharedStop(stepped, step.stopKind)
        let grouped = inProgress.filter { identity != nil && sharedStop($0, step.stopKind) == identity }
        let groupedRemaining = grouped.filter { needsThisWork($0) }
        if !groupedRemaining.isEmpty { return .groupedDeliveriesRemain(groupedRemaining) }

        let ungroupedRemaining: [Element] = switch step {
        case .pickedUp:
            // Grouped ones were answered above, so these are the ungrouped.
            inProgress.filter { awaitingPickup($0) }
        case .delivered:
            // Only an order already in the car could be handed over at this
            // door; one still to collect is not.
            inProgress.filter { state($0) == .pickedUp }
        }
        if !ungroupedRemaining.isEmpty { return .otherDeliveriesRemain(ungroupedRemaining) }

        let parkedPickups = inProgress.filter { parkedFor($0) && state($0) == .arrivedAtPickup }
        if !parkedPickups.isEmpty { return .parkedPickupRemains(parkedPickups) }

        return .complete
    }
}

/// What recording a Picked Up or Delivered did to a parked vehicle, under the
/// driver's `Resume driving after delivery progress` setting.
///
/// The step itself has already been recorded by the time any of these exists.
nonisolated enum ParkedProgressOutcome: Equatable, Sendable {
    /// The setting is off, the vehicle is not parked, or the step is not one
    /// that finishes work at a stop. The step did exactly what it always did.
    case notApplicable
    /// The stop has nothing left to record, and driving was recorded again.
    /// Carries the deliveries of that stop now past this step, by number.
    case resumed(step: ParkedProgressStep, deliveryNumbers: [Int])
    /// The vehicle stays parked because grouped deliveries still need this
    /// stop's work.
    case stillParkedForGroup(step: ParkedProgressStep, remaining: [Int])
    /// The vehicle stays parked because orders the driver did not group still
    /// need the same kind of work.
    case stillParkedForOtherOrders(step: ParkedProgressStep, remaining: [Int])
    /// The vehicle stays parked because a delivery the stretch was chosen for
    /// is still waiting for Resume Driving to record its pickup.
    case stillParkedForParkedPickup(remaining: [Int])
    /// The stop was done and driving could not be recorded. The step stands and
    /// the vehicle is still parked.
    case resumeNotRecorded(step: ParkedProgressStep, deliveryNumbers: [Int])

    static let settingName = "Resume driving after delivery progress"

    /// The line shown after the step, or `nil` when there is nothing to add.
    ///
    /// Says what the driver's setting did and why, and never that DashPilot
    /// saw the vehicle move or the driver leave: it did not.
    var notice: PickupWorkflowNotice? {
        switch self {
        case .notApplicable:
            return nil
        case let .resumed(step, numbers):
            let title = "\(PickupWorkflowNotice.names(numbers)) \(step.pastTense) · driving resumed"
            let detail = "Route recording restarted by your setting. Nothing is left to record at this stop."
            return PickupWorkflowNotice(
                title: title,
                detail: detail,
                spokenLabel: """
                \(PickupWorkflowNotice.names(numbers)) \(step.pastTense). Driving resumed by your \
                \(Self.settingName) setting, because nothing is left to record at this stop. DashPilot is \
                recording your route again.
                """,
                symbolName: "car.fill",
                recordedAnEvent: true
            )
        case let .stillParkedForGroup(step, remaining):
            let verb = remaining.count == 1 ? "needs" : "need"
            return Self.stillParked(
                "\(PickupWorkflowNotice.names(remaining)) still \(verb) \(Self.work(step)) at this stop."
            )
        case let .stillParkedForOtherOrders(step, remaining):
            let verb = remaining.count == 1 ? "needs" : "need"
            return Self.stillParked(
                "\(PickupWorkflowNotice.names(remaining)) still \(verb) \(Self.work(step))."
            )
        case let .stillParkedForParkedPickup(remaining):
            let verb = remaining.count == 1 ? "is" : "are"
            return Self.stillParked(
                "\(PickupWorkflowNotice.names(remaining)) \(verb) still at Arrived at Pickup."
            )
        case let .resumeNotRecorded(step, numbers):
            return PickupWorkflowNotice(
                title: "\(PickupWorkflowNotice.names(numbers)) \(step.pastTense) · still parked",
                detail: "Driving could not be recorded. Tap Resume Driving.",
                spokenLabel: """
                \(PickupWorkflowNotice.names(numbers)) \(step.pastTense). Driving could not be recorded, so \
                the vehicle is still parked. Tap Resume Driving.
                """,
                symbolName: "info.circle",
                recordedAnEvent: false
            )
        }
    }

    private static func work(_ step: ParkedProgressStep) -> String {
        switch step {
        case .pickedUp: "pickup"
        case .delivered: "drop-off"
        }
    }

    private static func stillParked(_ detail: String) -> PickupWorkflowNotice {
        let title = "Still parked"
        return PickupWorkflowNotice(
            title: title,
            detail: detail,
            spokenLabel: "\(title). \(detail) Tap Resume Driving when you leave.",
            symbolName: "parkingsign.circle",
            recordedAnEvent: false
        )
    }
}

/// One step the driver recorded while parked, and the driving it automatically
/// resumed, as the one thing an Undo takes back.
///
/// Screen state, like ``AutomatedPickupAction``: held for the app's short
/// undo window and gone after it, after a relaunch, and on every surface with
/// no screen to offer it on. What makes taking it back safe is
/// ``ParkedProgressUndo``'s check against the store, never this value.
nonisolated struct ParkedProgressAction: Equatable, Sendable, Identifiable {
    let step: ParkedProgressStep
    let deliveryID: UUID
    let deliveryNumber: Int?
    /// The instant the step was recorded at, read back after the write.
    let recordedAt: Date
    /// The parked stretch the step closed.
    let suspensionID: UUID
    /// The instant that stretch was closed at, read back after the write.
    let resumedAt: Date

    var id: String { "\(deliveryID.uuidString)-\(step.rawValue)-\(recordedAt.timeIntervalSinceReferenceDate)" }

    private var deliveryName: String {
        deliveryNumber.map(NumberedDelivery.title(number:)) ?? "The delivery"
    }

    private var eventName: String {
        switch step {
        case .pickedUp: "Picked Up"
        case .delivered: "Delivered"
        }
    }

    /// What VoiceOver says for the Undo control.
    var spokenUndoLabel: String {
        "Undo \(eventName) for \(deliveryName), and go back to parked. Route recording stops again."
    }

    /// What the line says once it has been taken back.
    var undoneNotice: PickupWorkflowNotice {
        let title = "Undid \(eventName) for \(deliveryName)"
        let detail = "The vehicle is parked again, and route recording is stopped."
        return PickupWorkflowNotice(
            title: title,
            detail: detail,
            spokenLabel: "\(title). \(detail)",
            symbolName: "arrow.uturn.backward.circle",
            recordedAnEvent: false
        )
    }
}

/// Why a step and the driving it resumed cannot be taken back together.
nonisolated enum ParkedProgressUndoRefusal: Error, CaseIterable, Equatable, Sendable {
    /// The delivery no longer records this step at this instant.
    case stepNoLongerRecorded
    /// Something was recorded on the delivery after the step.
    case laterEventRecorded
    /// The pickup at this instant was not the driver's own.
    case notRecordedByTheDriver
    /// The shift has ended or is paused, or the vehicle was parked again, or
    /// the parked stretch is no longer the one the step closed at that instant.
    case vehicleStateChanged
}

/// The rule for taking back a step and the driving it automatically resumed,
/// **both or neither**.
///
/// The step is judged as the delivery's own latest event, at the instant it
/// was recorded and, for a pickup, recorded by the driver. The vehicle is
/// judged as still driving since **that** stretch closed, on a running shift:
/// a newer stretch, a pause or an end is a later decision the Undo must not
/// rewrite. Any refusal refuses the whole Undo.
nonisolated struct ParkedProgressUndo: Equatable, Sendable {
    /// The state the delivery goes back to.
    let restoredState: DeliveryState

    /// - Parameters:
    ///   - action: what was recorded.
    ///   - record: the delivery's lifecycle, as stored now.
    ///   - pickupProvenance: its stored pickup provenance.
    ///   - shiftIsRunning: the shift has not ended and is not paused.
    ///   - latestSuspension: the shift's most recent parked stretch, as
    ///     `(id, endedAt)`, or `nil` when it has none.
    /// - Throws: ``ParkedProgressUndoRefusal``.
    init(
        undoing action: ParkedProgressAction,
        record: DeliveryLifecycleRecord,
        pickupProvenance: PickupProvenance?,
        shiftIsRunning: Bool,
        latestSuspension: (id: UUID, endedAt: Date?)?
    ) throws {
        switch action.step {
        case .pickedUp:
            guard record.pickedUpAt == action.recordedAt else { throw ParkedProgressUndoRefusal.stepNoLongerRecorded }
            guard record.state == .pickedUp else { throw ParkedProgressUndoRefusal.laterEventRecorded }
            guard pickupProvenance == .manual else { throw ParkedProgressUndoRefusal.notRecordedByTheDriver }
            restoredState = record.arrivedAtPickupAt == nil ? .accepted : .arrivedAtPickup
        case .delivered:
            guard record.deliveredAt == action.recordedAt else { throw ParkedProgressUndoRefusal.stepNoLongerRecorded }
            guard record.state == .delivered else { throw ParkedProgressUndoRefusal.laterEventRecorded }
            guard let recovery = try? DeliveryRecovery(reopening: record) else {
                throw ParkedProgressUndoRefusal.stepNoLongerRecorded
            }
            restoredState = recovery.restoredState
        }

        guard shiftIsRunning,
              let latestSuspension,
              latestSuspension.id == action.suspensionID,
              latestSuspension.endedAt == action.resumedAt
        else { throw ParkedProgressUndoRefusal.vehicleStateChanged }
    }
}
