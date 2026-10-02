import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// An explicit Delivered with several deliveries in progress: the rule, the
/// service Siri and the Lock Screen share, and the control the card offers.
///
/// What is pinned:
///
/// - The target is the **lowest-numbered picked-up** delivery, whatever order
///   the candidates arrive in, and never one that is not picked up.
/// - One press records **one** delivery, Same drop-off or not.
/// - The step goes through ``DeliveryProgressService``, so a parked vehicle is
///   handled by the existing `Resume driving after delivery progress` rule.
/// - A Lock Screen control drawn for one delivery never records another.
/// - "Record the next step" still refuses with two in progress.
@MainActor
@Suite("Stacked Delivered")
struct StackedDeliveredTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @MainActor
    private struct Store {
        let context: ModelContext
        let shift: Shift
        let deliveries: DeliveryService
        let intents: IntentLifecycleService

        func content(at date: Date) -> ShiftActivityAttributes.ContentState {
            ShiftLiveActivityService.content(
                for: shift, recordedDistance: .none, asOf: date, locale: Locale(identifier: "en_US"), context: context
            )
        }

        func states() -> [DeliveryState] { shift.deliveriesInOrder.map(\.state) }

        func pickUp(_ delivery: Delivery, at date: Date) throws {
            try deliveries.markArrivedAtPickup(delivery, at: date)
            try deliveries.markPickedUp(delivery, at: date.addingTimeInterval(30))
        }
    }

    private func makeStore(workflow: Bool = false, resumeAfterProgress: Bool = false) throws -> Store {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(workflow)
        try settings.setResumesDrivingAfterDeliveryProgress(resumeAfterProgress)
        return Store(
            context: context,
            shift: shift,
            deliveries: DeliveryService(context: context),
            intents: IntentLifecycleService(context: context)
        )
    }

    // MARK: The rule

    private struct Candidate: Equatable {
        let number: Int
        let state: DeliveryState
    }

    private func target(_ candidates: [Candidate]) -> Int? {
        OrderedDeliveryCompletion.target(among: candidates, number: \.number, state: \.state)?.number
    }

    @Test("The lowest-numbered picked-up delivery, whatever order the candidates arrive in")
    func lowestPickedUp() {
        #expect(target([Candidate(number: 3, state: .pickedUp), Candidate(number: 4, state: .pickedUp)]) == 3)
        #expect(target([Candidate(number: 4, state: .pickedUp), Candidate(number: 3, state: .pickedUp)]) == 3)
        #expect(target([5, 2, 9, 4].map { Candidate(number: $0, state: .pickedUp) }) == 2)
        #expect(target([Candidate(number: 1, state: .pickedUp)]) == 1)
    }

    @Test("Never a delivery that is not picked up, however low its number")
    func onlyPickedUpIsEligible() {
        let mixed = [
            Candidate(number: 1, state: .accepted),
            Candidate(number: 2, state: .arrivedAtPickup),
            Candidate(number: 3, state: .delivered),
            Candidate(number: 4, state: .cancelled),
            Candidate(number: 5, state: .pickedUp)
        ]
        #expect(target(mixed) == 5)
        #expect(target(Array(mixed.prefix(4))) == nil)
        #expect(target([]) == nil)
    }

    // MARK: The service

    @Test("Two picked up: one press records Delivery 1, the next records Delivery 2, then nothing is left")
    func twoInOrder() throws {
        let store = try makeStore()
        let pair = try store.deliveries.startOffer(deliveryCount: 2, at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }

        #expect(try store.intents.recordDelivered(at: at(10)) == .deliveryEventRecorded(number: 1, state: .delivered))
        #expect(store.states() == [.delivered, .pickedUp], "One press records one delivery")

        #expect(try store.intents.recordDelivered(at: at(20)) == .deliveryEventRecorded(number: 2, state: .delivered))
        #expect(store.states() == [.delivered, .delivered])

        #expect(throws: IntentLifecycleError.noDeliveryInProgress) { try store.intents.recordDelivered(at: at(30)) }
    }

    @Test("Three or more: strictly in number order")
    func threeInOrder() throws {
        let store = try makeStore()
        let first = try store.deliveries.startDelivery(at: at(1))
        let second = try store.deliveries.startDelivery(at: at(2))
        let third = try store.deliveries.startDelivery(at: at(3))
        // Picked up out of order: the record is still delivered by number.
        try store.pickUp(third, at: at(4))
        try store.pickUp(first, at: at(5))
        try store.pickUp(second, at: at(6))

        var recorded: [Int?] = []
        for minute in [10.0, 11, 12] {
            if case let .deliveryEventRecorded(number, _, _) = try store.intents.recordDelivered(at: at(minute)) {
                recorded.append(number)
            }
        }
        #expect(recorded == [1, 2, 3])
    }

    @Test("Mixed states: only the picked-up order moves, and the one still to collect is refused")
    func mixedStates() throws {
        let store = try makeStore()
        _ = try store.deliveries.startDelivery(at: at(1))
        let second = try store.deliveries.startDelivery(at: at(2))
        try store.pickUp(second, at: at(3))

        #expect(try store.intents.recordDelivered(at: at(10)) == .deliveryEventRecorded(number: 2, state: .delivered))
        #expect(store.states() == [.accepted, .delivered])

        #expect(throws: IntentLifecycleError.noDeliveryPickedUp) { try store.intents.recordDelivered(at: at(11)) }
        #expect(store.states() == [.accepted, .delivered], "A refusal moves nothing")
    }

    @Test("A cancelled or finished sibling is skipped, and its record is untouched")
    func terminalSiblingsAreSkipped() throws {
        let store = try makeStore()
        let first = try store.deliveries.startDelivery(at: at(1))
        let second = try store.deliveries.startDelivery(at: at(2))
        let third = try store.deliveries.startDelivery(at: at(3))
        let fourth = try store.deliveries.startDelivery(at: at(4))
        try store.deliveries.cancelDelivery(first, at: at(5))
        try store.pickUp(second, at: at(6))
        try store.deliveries.markDelivered(second, at: at(7))
        try store.pickUp(third, at: at(8))
        try store.pickUp(fourth, at: at(9))
        let cancelledAt = first.cancelledAt
        let deliveredAt = second.deliveredAt

        #expect(try store.intents.recordDelivered(at: at(12)) == .deliveryEventRecorded(number: 3, state: .delivered))
        #expect(store.states() == [.cancelled, .delivered, .delivered, .pickedUp])
        #expect(first.cancelledAt == cancelledAt)
        #expect(second.deliveredAt == deliveredAt)
    }

    @Test("Same drop-off, Same pickup, or both: one press still records one delivery")
    func sharedStopsDeliverOneAtATime() throws {
        for sharing: Set<SharedStopKind> in [[.dropOff], [.pickup], [.pickup, .dropOff]] {
            let store = try makeStore()
            let pair = try store.deliveries.startOffer(deliveryCount: 2, sharing: sharing, at: at(1)).deliveriesInOrder
            for delivery in pair { try store.pickUp(delivery, at: at(2)) }

            _ = try store.intents.recordDelivered(at: at(10))
            #expect(store.states() == [.delivered, .pickedUp], "\(sharing)")
            #expect(pair[1].deliveredAt == nil, "\(sharing): the grouped sibling is not delivered with it")
        }
    }

    @Test("Paused or with no shift running, there is nothing to deliver")
    func pausedAndNoShift() throws {
        let store = try makeStore()
        try ShiftService(context: store.context).pauseActiveShift(at: at(1))
        #expect(throws: IntentLifecycleError.noDeliveryInProgress) { try store.intents.recordDelivered(at: at(2)) }

        try ShiftService(context: store.context).endActiveShift(at: at(3))
        #expect(throws: IntentLifecycleError.delivery(.noActiveShift)) { try store.intents.recordDelivered(at: at(4)) }
    }

    @Test("A control drawn for one delivery never records another")
    func staleControlRecordsNothing() throws {
        let store = try makeStore()
        let pair = try store.deliveries.startOffer(deliveryCount: 2, at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }

        // The card said Delivered 1; Delivery 1 was then delivered in the app.
        try DeliveryProgressService(context: store.context).record(.delivered, of: pair[0], at: at(5))
        #expect(throws: IntentLifecycleError.deliveredTargetChanged) {
            try store.intents.recordDelivered(at: at(6), expected: pair[0].id)
        }
        #expect(pair[1].state == .pickedUp, "Delivery 2 is not recorded in its place")

        // The same press against the card as it now stands records Delivery 2.
        #expect(try store.intents.recordDelivered(at: at(7), expected: pair[1].id)
            == .deliveryEventRecorded(number: 2, state: .delivered))
    }

    @Test("Record the next step still refuses with two in progress, even when both are picked up")
    func genericStepStillRefuses() throws {
        let store = try makeStore()
        let pair = try store.deliveries.startOffer(deliveryCount: 2, at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }

        #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
            try store.intents.recordDeliveryProgress(at: at(3))
        }
        #expect(store.states() == [.pickedUp, .pickedUp])
    }

    // MARK: Parked

    @Test("Parked, setting off: Delivered records the step and the vehicle stays parked")
    func parkedSettingOff() throws {
        let store = try makeStore()
        let pair = try store.deliveries.startOffer(deliveryCount: 2, at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }
        _ = try ParkVehicleService(context: store.context).park(at: at(5))

        #expect(try store.intents.recordDelivered(at: at(6)) == .deliveryEventRecorded(number: 1, state: .delivered))
        #expect(store.shift.isRouteSuspended)
    }

    @Test("Parked, setting on, unmarked pair: stays parked after the first, resumes after the last")
    func parkedUnmarkedPair() throws {
        let store = try makeStore(resumeAfterProgress: true)
        let pair = try store.deliveries.startOffer(deliveryCount: 2, at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }
        _ = try ParkVehicleService(context: store.context).park(at: at(5))

        #expect(try store.intents.recordDelivered(at: at(6)) == .deliveryEventRecorded(
            number: 1, state: .delivered, parked: .stillParkedForOtherOrders(step: .delivered, remaining: [2])
        ))
        #expect(store.shift.isRouteSuspended)

        #expect(try store.intents.recordDelivered(at: at(7)) == .deliveryEventRecorded(
            number: 2, state: .delivered, parked: .resumed(step: .delivered, deliveryNumbers: [2])
        ))
        #expect(!store.shift.isRouteSuspended)
        #expect(store.shift.routeSuspensions.first?.endedAt == at(7), "Driving resumes at the step's own instant")
    }

    @Test("Parked, setting on, Same drop-off pair: the group keeps it parked until both are delivered")
    func parkedSameDropOff() throws {
        let store = try makeStore(resumeAfterProgress: true)
        let pair = try store.deliveries.startOffer(deliveryCount: 2, sharing: [.dropOff], at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }
        _ = try ParkVehicleService(context: store.context).park(at: at(5))

        #expect(try store.intents.recordDelivered(at: at(6)) == .deliveryEventRecorded(
            number: 1, state: .delivered, parked: .stillParkedForGroup(step: .delivered, remaining: [2])
        ))
        #expect(try store.intents.recordDelivered(at: at(7)) == .deliveryEventRecorded(
            number: 2, state: .delivered, parked: .resumed(step: .delivered, deliveryNumbers: [1, 2])
        ))
        #expect(!store.shift.isRouteSuspended)
    }

    // MARK: The Live Activity

    @Test("One delivery keeps its own step control; nothing ordered is offered")
    func oneDeliveryUnchanged() throws {
        let store = try makeStore()
        let delivery = try store.deliveries.startDelivery(at: at(1))
        try store.pickUp(delivery, at: at(2))
        #expect(store.content(at: at(3)).controls == [.deliveryStep(.complete), .startDelivery, .park])
    }

    @Test("Two picked up: Delivered names the lowest, and each press moves the card to the next")
    func cardFollowsThePresses() throws {
        let store = try makeStore()
        let pair = try store.deliveries.startOffer(deliveryCount: 2, at: at(1)).deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }

        let before = store.content(at: at(3))
        let first = ShiftActivityControl.nextDelivered(number: 1, deliveryID: pair[0].id)
        #expect(before.controls == [first, .startDelivery, .park])
        #expect(ShiftActivityControl.emphasised(in: before.controls) == first)
        #expect(before.controlNotice == nil, "A step is offered, so nothing says one is withheld")
        #expect(first.title == "Delivered 1")
        #expect(first.spokenLabel == "Mark delivery 1 delivered")

        _ = try store.intents.recordDelivered(at: at(4), expected: pair[0].id)
        // One left: the ordinary step of the one delivery in progress.
        #expect(store.content(at: at(5)).controls == [.deliveryStep(.complete), .startDelivery, .park])
    }

    @Test("Three picked up: the lowest is named; mixed: the picked-up one is named")
    func threeAndMixed() throws {
        let store = try makeStore()
        let first = try store.deliveries.startDelivery(at: at(1))
        let second = try store.deliveries.startDelivery(at: at(2))
        let third = try store.deliveries.startDelivery(at: at(3))
        try store.pickUp(third, at: at(4))
        #expect(store.content(at: at(5)).controls.first == .nextDelivered(number: 3, deliveryID: third.id))

        try store.pickUp(second, at: at(6))
        try store.pickUp(first, at: at(7))
        #expect(store.content(at: at(8)).controls.first == .nextDelivered(number: 1, deliveryID: first.id))
    }

    @Test("Nothing picked up: no Delivered, and the card says why no step is offered")
    func nothingPickedUp() throws {
        let store = try makeStore()
        _ = try store.deliveries.startOffer(deliveryCount: 2, at: at(1))
        let content = store.content(at: at(2))
        #expect(content.controls == [.startDelivery, .park])
        #expect(content.controlNotice != nil)
    }

    @Test("Workflow on keeps Park first; parked keeps Resume Driving first; Delivered stays on the card")
    func priorityUnderTheWorkflow() throws {
        let store = try makeStore(workflow: true)
        let pair = try store.deliveries.startOffer(deliveryCount: 2, sharing: [.pickup, .dropOff], at: at(1))
            .deliveriesInOrder
        for delivery in pair { try store.pickUp(delivery, at: at(2)) }
        let delivered = ShiftActivityControl.nextDelivered(number: 1, deliveryID: pair[0].id)

        let driving = store.content(at: at(3)).controls
        #expect(driving == [.park, delivered, .startDelivery])
        #expect(ShiftActivityControl.emphasised(in: driving) == .park)

        _ = try ParkVehicleService(context: store.context).park(at: at(4))
        let parked = store.content(at: at(5))
        #expect(parked.controls == [.resumeDriving, delivered, .startDelivery])
        #expect(ShiftActivityControl.emphasised(in: parked.controls) == .resumeDriving)
        #expect(parked.activeDeliveryTimers.map(\.title) == ["Deliveries 1 and 2"], "The row still merges")
    }

    @Test("Paused: Resume Shift and End only")
    func pausedOffersNoDelivered() throws {
        let store = try makeStore(workflow: true)
        try ShiftService(context: store.context).pauseActiveShift(at: at(1))
        #expect(store.content(at: at(2)).controls == [.resume, .end])
    }

    @Test("A snapshot carrying the new control round-trips")
    func controlCodable() throws {
        let control = ShiftActivityControl.nextDelivered(number: 4, deliveryID: UUID())
        let data = try JSONEncoder().encode([control, .startDelivery])
        #expect(try JSONDecoder().decode([ShiftActivityControl].self, from: data) == [control, .startDelivery])
    }
}
