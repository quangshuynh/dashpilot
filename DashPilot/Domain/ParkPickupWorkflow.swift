import Foundation

/// The driver's two answers about the Park and Resume pickup workflow.
///
/// Read by ``ParkVehicleService`` at the moment Park or Resume Driving is
/// pressed, and never copied onto anything recorded. Both are off unless the
/// driver turns them on, and ``handlesStackedOrdersInOrder`` means nothing while
/// ``usesParkAndResume`` is off.
nonisolated struct PickupWorkflowPreferences: Equatable, Sendable {
    /// Park records Arrived at Pickup, and Resume Driving then records Picked
    /// Up, for the delivery ``ParkPickupSelection`` names.
    let usesParkAndResume: Bool

    /// With more than one delivery in progress, the workflow works on the first
    /// one still waiting for its pickup, in delivery-number order. Off, it acts
    /// only while exactly one delivery is in progress.
    let handlesStackedOrdersInOrder: Bool

    /// Everything off: a driver who never opened Settings, or a store that
    /// could not be read.
    static let off = PickupWorkflowPreferences(usesParkAndResume: false, handlesStackedOrdersInOrder: false)
}

/// Which delivery a press of Park works on under the pickup workflow.
///
/// ## The workflow it serves
///
/// The driver parks at a pickup, walks in, waits, collects the order, walks
/// back and drives off. With the workflow on, **Park** records Arrived at
/// Pickup and **Resume Driving** records Picked Up, both for one delivery,
/// through the same operations the delivery's card calls. This type decides
/// which delivery that is, at Park. Resume does not choose again: it acts on
/// the delivery Park chose, which the parked stretch stores. See
/// ``RouteSuspension/pickupWorkflowDeliveryID``.
///
/// ## Which deliveries can be chosen
///
/// Only a delivery **still waiting for its pickup**: Accepted, or Arrived at
/// Pickup. A delivery already picked up is in the car and a finished one is
/// over, so neither can be the reason the driver parked at a pickup, and
/// neither is ever moved. An Arrived at Pickup delivery can be chosen, which
/// records nothing at Park (it is already there) and lets Resume record its
/// pickup.
///
/// ## Which one, with more than one in progress
///
/// **The first in the driver's recorded order**: the lowest delivery number
/// among those still waiting for their pickup. A delivery's number is its
/// position in ``Delivery/acceptedBefore(_:_:)``, acceptance time with the
/// identifier as a tie-break, which is the number its card, its history and
/// every confirmation already show, and neither half can change while the shift
/// runs. So the choice is total and repeatable, and it is the same delivery the
/// driver reads as "Delivery 3". Nothing else is consulted: no position, no
/// distance, no pickup place, no expected pay, no age, and not the order a
/// store or a screen happens to list them in, which is why the elements are
/// sorted here rather than trusted as given.
///
/// That rule applies only when the driver turned on
/// ``PickupWorkflowPreferences/handlesStackedOrdersInOrder``. Without it the
/// workflow acts only while **exactly one** delivery is in progress, which is
/// the unambiguous case: with two orders running, the one Park acts on would be
/// chosen by a rule the driver has not agreed to.
///
/// Two deliveries both at Arrived at Pickup are ordered the same way: the lower
/// number is chosen and the other waits for the next Park.
///
/// ## A pickup the driver said is shared
///
/// The one exception to "one delivery per Park", and it is the driver's own
/// statement rather than anything inferred. When the chosen delivery was
/// recorded as collected at the **same pickup** as others in its offer
/// (``SharedStopKind/pickup``), every one of those still waiting for its pickup
/// is chosen with it, lowest number first, because the driver said they are one
/// counter and one handover. Nothing else joins them: not a delivery going to
/// the same drop-off (one customer can order from two restaurants), not one
/// accepted in the same offer, not one naming the same pickup place.
///
/// The same statement answers the stacked-orders question. With stacked orders
/// off, the workflow acts only when there is no choice to make, and deliveries
/// the driver said share one pickup are one stop: if **every** delivery in
/// progress shares the chosen delivery's pickup, Park acts on them without
/// the stacked-order rule. Any unrelated order in progress beside them is
/// still a choice the driver has not agreed to, and nothing is chosen.
///
/// Generic over the element, like ``UnambiguousDelivery``: the service resolves
/// a `Delivery`, and the tests resolve plain values.
nonisolated enum ParkPickupSelection<Element> {
    /// The delivery this Park works on.
    case target(Element)
    /// Two or more deliveries the driver recorded as sharing one pickup, all
    /// still waiting for it, lowest number first. The first is the one the
    /// ordinary rule chose.
    case sharedPickup([Element])
    /// More than one delivery is in progress and the driver has not asked for
    /// stacked orders to be handled, so none is chosen. Carries how many are in
    /// progress.
    case stackedNotHandled(inProgress: Int)
    /// No delivery in progress is waiting for its pickup: nothing is running,
    /// or every order is already in the car.
    case noneAwaitingPickup

    /// The whole rule.
    ///
    /// - Parameters:
    ///   - active: the deliveries in progress, in any order.
    ///   - handlesStackedOrdersInOrder: the driver's stacked-order answer.
    ///   - number: each delivery's number in its shift.
    ///   - state: each delivery's state.
    ///   - sharedPickup: each delivery's shared-pickup identity, which the
    ///     driver recorded or did not. Nothing else about a delivery can join
    ///     two of them.
    static func select(
        among active: [Element],
        handlesStackedOrdersInOrder: Bool,
        number: (Element) -> Int,
        state: (Element) -> DeliveryState,
        sharedPickup: (Element) -> UUID? = { _ in nil }
    ) -> Self {
        let inProgress = active.filter { state($0).isActive }
        let awaitingPickup = inProgress
            .filter { state($0) == .accepted || state($0) == .arrivedAtPickup }
            .sorted { number($0) < number($1) }

        guard let first = awaitingPickup.first else { return .noneAwaitingPickup }

        let pickup = sharedPickup(first)
        // One stop in progress, as far as the driver has said: a single
        // delivery, or deliveries that all share the chosen one's pickup.
        let oneStopInProgress = inProgress.count == 1
            || (pickup != nil && inProgress.allSatisfy { sharedPickup($0) == pickup })
        guard handlesStackedOrdersInOrder || oneStopInProgress else {
            return .stackedNotHandled(inProgress: inProgress.count)
        }

        guard let pickup else { return .target(first) }
        let together = awaitingPickup.filter { sharedPickup($0) == pickup }
        return together.count > 1 ? .sharedPickup(together) : .target(first)
    }
}

/// What a line about the workflow says, in print and aloud.
///
/// One shape for every outcome of Park and of Resume, so the app draws them one
/// way and the tests read them one way.
nonisolated struct PickupWorkflowNotice: Equatable, Sendable {
    /// What happened, naming the delivery.
    let title: String
    /// Why, or what to do next.
    let detail: String
    /// What VoiceOver says for the whole line.
    let spokenLabel: String
    /// A symbol that says what happened without relying on the tint it is drawn
    /// in.
    let symbolName: String
    /// Whether a delivery event was just recorded.
    let recordedAnEvent: Bool

    /// The printed pair as one sentence, for a voice confirmation.
    var sentence: String { "\(title). \(detail)" }

    static let settingName = "Pick up orders with Park & Resume"

    fileprivate static func name(_ number: Int?) -> String {
        guard let number else { return "Delivery" }
        return NumberedDelivery.title(number: number)
    }

    /// `Delivery 3`, `Deliveries 3 and 4`, `Deliveries 3, 4 and 5`.
    static func names(_ numbers: [Int]) -> String {
        let sorted = numbers.sorted()
        guard sorted.count > 1 else { return sorted.first.map(NumberedDelivery.title(number:)) ?? "No delivery" }
        return "Deliveries \(SharedStopDescription.list(sorted.map(String.init)))"
    }

    fileprivate static func possessive(_ number: Int?) -> String {
        guard let number else { return "The delivery's" }
        return "\(NumberedDelivery.title(number: number))'s"
    }

    fileprivate static func recorded(title: String, detail: String, stage: DeliveryState) -> Self {
        PickupWorkflowNotice(
            title: title,
            detail: detail,
            spokenLabel: "\(title). \(detail) Recorded by your \(settingName) setting, from your tap.",
            symbolName: stage.symbolName,
            recordedAnEvent: true
        )
    }

    fileprivate static func informational(title: String, detail: String) -> Self {
        PickupWorkflowNotice(
            title: title,
            detail: detail,
            spokenLabel: "\(title). \(detail)",
            symbolName: "info.circle",
            recordedAnEvent: false
        )
    }
}

/// What a press of Park did under the pickup workflow.
///
/// Parking has already been recorded by the time any of these exists: every
/// case describes a parked vehicle. The sentences say what was **recorded**
/// because of the driver's setting, and never that DashPilot saw a restaurant,
/// an order or a handover, because it did not.
nonisolated enum ParkPickupOutcome: Equatable, Sendable {
    /// The workflow is off. Parking did exactly what it always did.
    case notEnabled
    /// The delivery was recorded as Arrived at Pickup at the instant of parking.
    ///
    /// The number is optional for the reason every delivery number in a
    /// confirmation is: a delivery whose shift cannot be read is not given a
    /// name the app did not identify.
    case markedArrived(deliveryNumber: Int?)
    /// The delivery already had Arrived at Pickup recorded, so nothing was
    /// written; Resume Driving will record its pickup.
    case alreadyArrived(deliveryNumber: Int?)
    /// No delivery in progress is waiting for its pickup.
    case noneAwaitingPickup
    /// More than one delivery is in progress and stacked orders are not handled.
    case stackedNotHandled(inProgress: Int)
    /// A delivery was chosen and its arrival was refused or failed to save. The
    /// vehicle is still parked.
    case arrivalNotRecorded(deliveryNumber: Int?)
    /// The deliveries in progress could not be read, so none was chosen. The
    /// vehicle is still parked.
    case deliveriesUnreadable
    /// Deliveries the driver recorded as sharing one pickup were all chosen:
    /// the ones still at Accepted were recorded as Arrived at Pickup together,
    /// in one write, and the rest already had it.
    case sharedPickupArrived(SharedPickupArrival)
    /// Deliveries sharing one pickup were chosen and their arrival was refused
    /// or failed to save, **for all of them**: none was recorded. The vehicle is
    /// still parked.
    case sharedPickupArrivalNotRecorded(deliveryNumbers: [Int])

    /// The line under the parked notice, or `nil` when there is nothing to add
    /// to ordinary parking.
    ///
    /// Silent while the workflow is off, and silent when no order is waiting
    /// for a pickup: a driver parking with every order in the car is parking at
    /// a customer, and the workflow had no question to answer.
    var notice: PickupWorkflowNotice? {
        switch self {
        case .notEnabled, .noneAwaitingPickup:
            nil
        case let .markedArrived(number):
            .recorded(
                title: "\(PickupWorkflowNotice.name(number)) marked Arrived at Pickup",
                detail: "Recorded automatically when you parked.",
                stage: .arrivedAtPickup
            )
        case let .alreadyArrived(number):
            .informational(
                title: "\(PickupWorkflowNotice.name(number)) is at Arrived at Pickup",
                detail: "Resume Driving will mark it Picked Up."
            )
        case let .stackedNotHandled(count):
            .informational(
                title: "No delivery step recorded",
                detail: """
                \(count) deliveries are in progress and Handle stacked orders in order is off. \
                Record the step on the delivery's card.
                """
            )
        case let .arrivalNotRecorded(number):
            .informational(
                title: "\(PickupWorkflowNotice.possessive(number)) arrival was not recorded",
                detail: "Record it on the delivery's card. The vehicle is parked."
            )
        case .deliveriesUnreadable:
            .informational(
                title: "No delivery step recorded",
                detail: "DashPilot could not read the deliveries in progress. The vehicle is parked."
            )
        case let .sharedPickupArrived(arrival) where arrival.recorded.isEmpty:
            .informational(
                title: "\(PickupWorkflowNotice.names(arrival.alreadyArrived)) are at Arrived at Pickup",
                detail: "Resume Driving will mark them Picked Up."
            )
        case let .sharedPickupArrived(arrival):
            .recorded(
                title: "\(PickupWorkflowNotice.names(arrival.recorded)) marked Arrived at Pickup",
                detail: arrival.alreadyArrived.isEmpty
                    ? "Recorded automatically when you parked, for the deliveries you marked Same pickup."
                    : """
                    Recorded automatically when you parked, for the deliveries you marked Same pickup. \
                    \(PickupWorkflowNotice.names(arrival.alreadyArrived)) already had it.
                    """,
                stage: .arrivedAtPickup
            )
        case let .sharedPickupArrivalNotRecorded(numbers):
            .informational(
                title: "No arrival recorded for \(PickupWorkflowNotice.names(numbers))",
                detail: "Record it on each delivery's card. The vehicle is parked."
            )
        }
    }
}

/// What a shared-pickup Park recorded, by delivery number.
nonisolated struct SharedPickupArrival: Equatable, Sendable {
    /// Recorded as Arrived at Pickup by this press, together.
    let recorded: [Int]
    /// Chosen with them and already at Arrived at Pickup, so nothing was
    /// written; Resume Driving will record their pickup too.
    let alreadyArrived: [Int]
}

/// What a shared-pickup Resume Driving recorded, and why any delivery Park
/// chose was left alone, by delivery number.
nonisolated struct SharedPickupResume: Equatable, Sendable {
    /// Recorded as Picked Up by this press, together.
    let recorded: [Int]
    /// The driver had already recorded their pickup.
    let alreadyPickedUp: [Int]
    /// No longer at Arrived at Pickup, for example because the automated
    /// arrival was undone.
    let notAtPickup: [Int]
    /// Delivered or cancelled since Park, or no longer found.
    let noLongerInProgress: [Int]

    /// The sentences saying why the rest were left alone, in the order a driver
    /// would ask about them.
    var skippedSentences: [String] {
        var sentences: [String] = []
        if !alreadyPickedUp.isEmpty {
            sentences.append("\(PickupWorkflowNotice.names(alreadyPickedUp)) already had Picked Up recorded.")
        }
        if !notAtPickup.isEmpty {
            sentences.append("\(PickupWorkflowNotice.names(notAtPickup)) had no Arrived at Pickup recorded.")
        }
        if !noLongerInProgress.isEmpty {
            let verb = noLongerInProgress.count == 1 ? "is" : "are"
            sentences.append("\(PickupWorkflowNotice.names(noLongerInProgress)) \(verb) no longer in progress.")
        }
        return sentences
    }
}

/// What a press of Resume Driving did under the pickup workflow.
///
/// Driving has already been recorded by the time any of these exists. Only the
/// delivery Park chose for this parked stretch is ever considered, so a
/// different stacked order is never picked up because the first one changed
/// while the driver was inside.
nonisolated enum ResumePickupOutcome: Equatable, Sendable {
    /// The workflow is off now. Resuming did exactly what it always did.
    case notEnabled
    /// This parked stretch was not for any delivery's pickup.
    case noParkedPickup
    /// The delivery Park chose was recorded as Picked Up at the instant of
    /// resuming.
    case markedPickedUp(deliveryNumber: Int?)
    /// The driver already recorded that delivery's pickup themselves.
    case alreadyPickedUp(deliveryNumber: Int?)
    /// That delivery no longer has Arrived at Pickup recorded, for example
    /// because the automated arrival was undone.
    case notAtPickup(deliveryNumber: Int?)
    /// That delivery was delivered or cancelled, or can no longer be found.
    case noLongerInProgress(deliveryNumber: Int?)
    /// The pickup was refused or failed to save. The vehicle is driving again.
    case pickupNotRecorded(deliveryNumber: Int?)
    /// Park chose deliveries the driver recorded as sharing one pickup. Those
    /// still at Arrived at Pickup were recorded as Picked Up together, in one
    /// write, and the rest are named with the reason they were left alone.
    case sharedPickupPickedUp(SharedPickupResume)
    /// Their pickup was refused or failed to save, **for all of them**: none
    /// was recorded. The vehicle is driving again.
    case sharedPickupNotRecorded(deliveryNumbers: [Int])

    /// The line shown after resuming, or `nil` when there is nothing to add.
    var notice: PickupWorkflowNotice? {
        switch self {
        case .notEnabled, .noParkedPickup, .alreadyPickedUp:
            nil
        case let .markedPickedUp(number):
            .recorded(
                title: "\(PickupWorkflowNotice.name(number)) marked Picked Up",
                detail: "Recorded automatically when you resumed driving.",
                stage: .pickedUp
            )
        case let .notAtPickup(number):
            .informational(
                title: "\(PickupWorkflowNotice.possessive(number)) pickup was not recorded",
                detail: "It does not have Arrived at Pickup recorded. Record it on the delivery's card."
            )
        case let .noLongerInProgress(number):
            .informational(
                title: "No pickup recorded",
                detail: number.map { "\(NumberedDelivery.title(number: $0)) is no longer in progress." }
                    ?? "The delivery you parked for is no longer in progress."
            )
        case let .pickupNotRecorded(number):
            .informational(
                title: "\(PickupWorkflowNotice.possessive(number)) pickup was not recorded",
                detail: "Record it on the delivery's card. Route recording has resumed."
            )
        case let .sharedPickupPickedUp(resume) where resume.recorded.isEmpty:
            .informational(
                title: "No pickup recorded",
                detail: resume.skippedSentences.isEmpty
                    ? "The deliveries you parked for are no longer in progress."
                    : resume.skippedSentences.joined(separator: " ")
            )
        case let .sharedPickupPickedUp(resume):
            .recorded(
                title: "\(PickupWorkflowNotice.names(resume.recorded)) marked Picked Up",
                detail: (
                    ["Recorded automatically when you resumed driving, for the deliveries you marked Same pickup."]
                        + resume.skippedSentences
                ).joined(separator: " "),
                stage: .pickedUp
            )
        case let .sharedPickupNotRecorded(numbers):
            .informational(
                title: "No pickup recorded for \(PickupWorkflowNotice.names(numbers))",
                detail: "Record it on each delivery's card. Route recording has resumed."
            )
        }
    }
}
