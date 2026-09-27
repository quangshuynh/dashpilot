import Foundation

/// One lifecycle event the pickup workflow just recorded, as the app that
/// recorded it remembers it.
///
/// ## What it is for
///
/// Offering to take that one event back, and nothing else. Park recorded
/// Arrived at Pickup, or Resume Driving recorded Picked Up, for one delivery at
/// one instant; this is that fact, held by the screen that showed it.
///
/// ## Why it is not stored
///
/// It is a **short-lived offer**, held in view state for the same window the
/// app's immediate undo of a Delivered already uses, and gone after that, after
/// a relaunch, and on every surface that has no screen to offer it on (Siri,
/// Shortcuts, the Lock Screen). What makes taking the event back safe is not
/// this value but the check ``AutomatedPickupStepUndo`` makes against the store:
/// the delivery must still record exactly this event at exactly this instant,
/// with nothing after it. A pickup's provenance is stored and is checked too;
/// an arrival has no provenance, and its instant, compared with the one this
/// process just wrote, is what stands in for it, the way
/// ``DeliveryTimeCorrection`` refuses a proposal built against times that have
/// since moved.
nonisolated struct AutomatedPickupStep: Equatable, Hashable, Sendable, Identifiable {
    /// Which of the workflow's two events.
    nonisolated enum Kind: Equatable, Hashable, Sendable {
        /// Park recorded Arrived at Pickup.
        case arrivedWhenParked
        /// Resume Driving recorded Picked Up.
        case pickedUpWhenResumed
    }

    let kind: Kind
    let deliveryID: UUID
    /// The number the delivery's card shows, when it could be read.
    let deliveryNumber: Int?
    /// The instant the event was recorded at, read back from the delivery after
    /// the write.
    let recordedAt: Date

    var id: String { "\(deliveryID.uuidString)-\(kind)-\(recordedAt.timeIntervalSinceReferenceDate)" }

    /// The event this step recorded.
    var stage: DeliveryState {
        switch kind {
        case .arrivedWhenParked: .arrivedAtPickup
        case .pickedUpWhenResumed: .pickedUp
        }
    }

    /// The state taking it back returns the delivery to.
    var restoredState: DeliveryState {
        switch kind {
        case .arrivedWhenParked: .accepted
        case .pickedUpWhenResumed: .arrivedAtPickup
        }
    }

    private var deliveryName: String {
        deliveryNumber.map(NumberedDelivery.title(number:)) ?? "The delivery"
    }

    private var vehicleState: String {
        switch kind {
        case .arrivedWhenParked: "The vehicle is still parked."
        case .pickedUpWhenResumed: "The vehicle is still recorded as driving."
        }
    }

    private var eventName: String {
        switch kind {
        case .arrivedWhenParked: "Arrived at Pickup"
        case .pickedUpWhenResumed: "Picked Up"
        }
    }

    /// What VoiceOver says for the Undo control: which delivery, which event,
    /// what the delivery goes back to, and that the vehicle does not move.
    var spokenUndoLabel: String {
        """
        Undo \(eventName) for \(deliveryName). It goes back to \(restoredState.historyDescription). \
        \(vehicleState)
        """
    }

    /// What the line says once the event has been taken back.
    var undoneNotice: PickupWorkflowNotice {
        let title = "Undid \(eventName) for \(deliveryName)"
        let detail = "It is back to \(restoredState.historyDescription). \(vehicleState)"
        return PickupWorkflowNotice(
            title: title,
            detail: detail,
            spokenLabel: "\(title). \(detail)",
            symbolName: "arrow.uturn.backward.circle",
            recordedAnEvent: false
        )
    }
}

/// Why an automated event cannot be taken back.
nonisolated enum AutomatedStepUndoRefusal: Error, CaseIterable, Equatable, Sendable {
    /// The step names a different delivery. A caller defect, refused rather
    /// than applied to whichever delivery it was handed.
    case differentDelivery
    /// The delivery no longer records this event at this instant: it was
    /// already taken back, or recorded again since.
    case stepNoLongerRecorded
    /// Something was recorded after it: the delivery was picked up, delivered or
    /// cancelled since. Taking the event back would mean taking that back too,
    /// which this never does.
    case laterEventRecorded
    /// The pickup at this instant was not recorded by Resume Driving.
    case notRecordedAutomatically
}

/// The rule for taking back one event the pickup workflow recorded.
///
/// ## What it reverses, and what it leaves alone
///
/// **One delivery event.** Arrived at Pickup goes back to Accepted, or Picked Up
/// goes back to Arrived at Pickup, by removing that one timestamp. The vehicle
/// is **not** part of it: the parked stretch Park opened stays open, and the one
/// Resume closed stays closed, because the driver really did park and really is
/// driving. No other delivery, no other event and no other field moves.
///
/// ## When it refuses
///
/// Only the latest event can come back, and only while it is still the one the
/// workflow wrote. A delivery that has moved on, or whose event was taken back
/// or recorded again in between, is refused with the reason rather than rewound
/// through, because a cascade would remove events the driver recorded
/// themselves.
nonisolated struct AutomatedPickupStepUndo: Equatable, Sendable {
    let restoredState: DeliveryState

    /// - Parameters:
    ///   - step: the event the workflow recorded.
    ///   - deliveryID: the delivery it is about to be applied to.
    ///   - record: that delivery's lifecycle, as stored now.
    ///   - pickupProvenance: that delivery's stored pickup provenance.
    /// - Throws: ``AutomatedStepUndoRefusal``.
    init(
        undoing step: AutomatedPickupStep,
        deliveryID: UUID,
        record: DeliveryLifecycleRecord,
        pickupProvenance: PickupProvenance?
    ) throws {
        guard deliveryID == step.deliveryID else { throw AutomatedStepUndoRefusal.differentDelivery }

        switch step.kind {
        case .arrivedWhenParked:
            guard record.arrivedAtPickupAt == step.recordedAt else {
                throw AutomatedStepUndoRefusal.stepNoLongerRecorded
            }
            guard record.state == .arrivedAtPickup else { throw AutomatedStepUndoRefusal.laterEventRecorded }

        case .pickedUpWhenResumed:
            guard record.pickedUpAt == step.recordedAt else {
                throw AutomatedStepUndoRefusal.stepNoLongerRecorded
            }
            guard record.state == .pickedUp else { throw AutomatedStepUndoRefusal.laterEventRecorded }
            guard pickupProvenance == .resumeAutomation else {
                throw AutomatedStepUndoRefusal.notRecordedAutomatically
            }
        }

        restoredState = step.restoredState
    }
}
