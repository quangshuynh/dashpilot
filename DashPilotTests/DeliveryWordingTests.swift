import Foundation
import Testing
@testable import DashPilot

/// The sentences the delivery interface is allowed to say.
///
/// The wording lives in the domain rather than in a view so it can be asserted
/// here: a driver hears the spoken form, and a label that does not name the
/// event it records — or the delivery it records it against — is unusable by
/// voice.
@MainActor
@Suite("Delivery wording")
struct DeliveryWordingTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// A delivery attached to a shift, without a store: none of the wording
    /// below needs one.
    private func makeDelivery(acceptedAfter seconds: TimeInterval = 0) -> Delivery {
        Delivery(shift: Shift(startedAt: start), acceptedAt: start.addingTimeInterval(seconds))
    }

    // MARK: Next action

    @Test("Every active state offers exactly one next action")
    func offersOneNextAction() {
        #expect(DeliveryState.accepted.nextAction == .arriveAtPickup)
        #expect(DeliveryState.arrivedAtPickup.nextAction == .pickUp)
        #expect(DeliveryState.pickedUp.nextAction == .complete)
    }

    @Test("A finished delivery offers no next action")
    func finishedStatesOfferNothing() {
        #expect(DeliveryState.delivered.nextAction == nil)
        #expect(DeliveryState.cancelled.nextAction == nil)
        #expect(DeliveryState.delivered.isFinished)
        #expect(DeliveryState.cancelled.isFinished)
        #expect(DeliveryState.allCases.filter(\.isActive).count == 3)
    }

    @Test("The action a state offers records that state's successor")
    func nextActionRecordsTheFollowingState() {
        #expect(DeliveryState.accepted.nextAction?.recordedState == .arrivedAtPickup)
        #expect(DeliveryState.arrivedAtPickup.nextAction?.recordedState == .pickedUp)
        #expect(DeliveryState.pickedUp.nextAction?.recordedState == .delivered)
        #expect(DeliveryAction.start.recordedState == nil, "Starting creates a delivery rather than advancing one")
    }

    // MARK: Pickup place controls

    @Test("The pickup control says whether it adds or changes")
    func pickupControlNamesWhatItDoes() {
        let numbered = NumberedDelivery(number: 2, delivery: makeDelivery())

        #expect(numbered.pickupPlaceActionTitle(hasPlace: false) == "Add Pickup Place")
        #expect(numbered.pickupPlaceActionTitle(hasPlace: true) == "Change Pickup Place")
    }

    @Test("The pickup control names its delivery aloud")
    func pickupControlNamesItsDelivery() {
        let numbered = NumberedDelivery(number: 2, delivery: makeDelivery())

        #expect(numbered.spokenPickupPlaceLabel(hasPlace: false) == "Add pickup place for Delivery 2")
        #expect(numbered.spokenPickupPlaceLabel(hasPlace: true) == "Change pickup place for Delivery 2")
    }

    @Test("Every delivery's pickup control is distinguishable by what it says")
    func pickupControlsAreDistinguishable() {
        let spoken = (1...3).map { number in
            NumberedDelivery(number: number, delivery: makeDelivery(acceptedAfter: Double(number) * 60))
                .spokenPickupPlaceLabel(hasPlace: false)
        }

        #expect(
            Set(spoken).count == 3,
            "With three cards on screen, a control identified only by position is unusable without sight"
        )
    }

    // MARK: Labels

    @Test("Every action names the event it records, in print and aloud")
    func actionsNameTheirEvent() throws {
        let expected: [DeliveryAction: (title: String, spoken: String)] = [
            .start: ("Start Delivery", "Start delivery"),
            .arriveAtPickup: ("Arrived at Pickup", "Mark arrived at pickup"),
            .pickUp: ("Picked Up", "Mark order picked up"),
            .complete: ("Delivered", "Mark delivery completed")
        ]

        for action in DeliveryAction.allCases {
            let wording = try #require(expected[action])
            #expect(action.title == wording.title)
            #expect(action.spokenLabel == wording.spoken)
        }
    }

    @Test("No label is a bare 'Next' or otherwise unspecific")
    func labelsAreNeverAmbiguous() {
        let vague: Set<String> = ["Next", "Continue", "Done", "OK", "Advance", "Update"]
        for action in DeliveryAction.allCases {
            #expect(!vague.contains(action.title))
            #expect(!vague.contains(action.spokenLabel))
            #expect(action.spokenLabel.count > 8, "A spoken label has to be a phrase: \(action.spokenLabel)")
        }
    }

    @Test("Every state has a status phrase, a history name and a symbol")
    func statesDescribeThemselves() {
        for state in DeliveryState.allCases {
            #expect(!state.statusDescription.isEmpty)
            #expect(!state.historyDescription.isEmpty)
            #expect(!state.symbolName.isEmpty, "State must be distinguishable without colour: \(state)")
        }
        // Distinct symbols, so the icon carries the state rather than decorating it.
        #expect(Set(DeliveryState.allCases.map(\.symbolName)).count == DeliveryState.allCases.count)
    }

    // MARK: Summary

    @Test("An empty shift says so rather than showing a zero")
    func summarisesNothing() {
        let summary = DeliverySummary(states: [])

        #expect(summary.isEmpty)
        #expect(summary.recorded == 0)
        #expect(summary.statement == "No deliveries recorded")
        #expect(summary.spokenStatement == "No deliveries recorded")
    }

    @Test("Completed deliveries are counted and pluralised")
    func summarisesCompleted() {
        #expect(DeliverySummary(states: [.delivered]).statement == "1 delivery completed")
        #expect(DeliverySummary(states: [.delivered, .delivered]).statement == "2 deliveries completed")
    }

    @Test("A cancelled delivery is counted separately, never as completed")
    func countsCancellationsApart() {
        let summary = DeliverySummary(states: [.delivered, .delivered, .cancelled])

        #expect(summary.completed == 2)
        #expect(summary.cancelled == 1)
        #expect(summary.recorded == 3)
        #expect(summary.statement == "2 deliveries completed · 1 cancelled")
        #expect(summary.spokenStatement == "2 deliveries completed. 1 delivery cancelled")
    }

    @Test("A shift whose only delivery was cancelled does not claim a completion")
    func cancelledOnly() {
        let summary = DeliverySummary(states: [.cancelled])

        #expect(summary.statement == "1 cancelled")
        #expect(!summary.isEmpty, "A cancelled delivery is history, not an absence")
    }

    @Test("A delivery still running is counted as in progress")
    func countsInProgress() {
        let summary = DeliverySummary(states: [.delivered, .pickedUp])

        #expect(summary.inProgress == 1)
        #expect(summary.statement == "1 delivery completed · 1 still in progress")
        #expect(summary.spokenStatement == "1 delivery completed. 1 delivery still in progress")
    }

    @Test("Every active state counts as in progress")
    func everyActiveStateCountsAsInProgress() {
        let summary = DeliverySummary(states: [.accepted, .arrivedAtPickup, .pickedUp])

        #expect(summary.inProgress == 3)
        #expect(summary.completed == 0)
        #expect(summary.cancelled == 0)
    }

    @Test("The running-shift headline counts what is being worked right now")
    func statesHowManyAreInProgress() {
        #expect(DeliverySummary(states: []).inProgressStatement == "No delivery in progress")
        #expect(DeliverySummary(states: [.delivered]).inProgressStatement == "No delivery in progress")
        #expect(DeliverySummary(states: [.accepted]).inProgressStatement == "1 delivery in progress")
        #expect(
            DeliverySummary(states: [.accepted, .pickedUp]).inProgressStatement == "2 deliveries in progress"
        )
        #expect(
            DeliverySummary(states: [.delivered, .accepted, .pickedUp, .cancelled]).inProgressStatement
                == "2 deliveries in progress",
            "Only the unfinished ones are being worked"
        )
    }

    // MARK: Numbering

    @Test("Deliveries are numbered from one, in the order they were accepted")
    func numbersDeliveriesFromOne() {
        let early = makeDelivery(acceptedAfter: 300)
        let middle = makeDelivery(acceptedAfter: 900)
        let late = makeDelivery(acceptedAfter: 1_500)

        let numbered = NumberedDelivery.numbering([late, early, middle])

        #expect(numbered.map(\.number) == [1, 2, 3])
        #expect(numbered.map(\.delivery.id) == [early.id, middle.id, late.id])
        #expect(numbered.map(\.title) == ["Delivery 1", "Delivery 2", "Delivery 3"])
        #expect(numbered.map(\.id) == [early.id, middle.id, late.id], "A card is identified by its delivery")
    }

    @Test("Numbering is repeatable whatever order the deliveries arrive in")
    func numberingIsRepeatable() {
        let first = makeDelivery(acceptedAfter: 300)
        let second = makeDelivery(acceptedAfter: 900)

        let forwards = NumberedDelivery.numbering([first, second])
        let backwards = NumberedDelivery.numbering([second, first])

        #expect(forwards.map(\.number) == backwards.map(\.number))
        #expect(forwards.map(\.delivery.id) == backwards.map(\.delivery.id))
    }

    @Test("A numbered delivery names itself and its state, in print and aloud")
    func numberedDeliveriesDescribeThemselves() throws {
        let delivery = makeDelivery()
        try delivery.markArrivedAtPickup(at: start.addingTimeInterval(300))
        let numbered = NumberedDelivery(number: 2, delivery: delivery)

        #expect(numbered.title == "Delivery 2")
        #expect(numbered.statusTitle == "Delivery 2 · Waiting at the pickup")
        #expect(numbered.spokenStatus == "Delivery 2, waiting at the pickup")
    }

    @Test("Every control names the delivery it acts on")
    func controlsNameTheirDelivery() {
        let numbered = NumberedDelivery(number: 3, delivery: makeDelivery())

        #expect(numbered.spokenLabel(for: .arriveAtPickup) == "Delivery 3. Mark arrived at pickup")
        #expect(numbered.spokenLabel(for: .pickUp) == "Delivery 3. Mark order picked up")
        #expect(numbered.spokenLabel(for: .complete) == "Delivery 3. Mark delivery completed")
        #expect(numbered.spokenCancelLabel == "Delivery 3. Cancel this delivery")

        // With several cards on screen, a spoken label that does not name its
        // delivery identifies its target by position alone.
        for action in DeliveryAction.allCases {
            #expect(numbered.spokenLabel(for: action).hasPrefix("Delivery 3."))
        }
    }
}
