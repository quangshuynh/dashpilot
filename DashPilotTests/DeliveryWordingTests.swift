import Foundation
import Testing
@testable import DashPilot

/// The sentences the delivery interface is allowed to say.
///
/// The wording lives in the domain rather than in a view so it can be asserted
/// here: a driver hears the spoken form, and a label that does not name the
/// event it records is unusable by voice.
@Suite("Delivery wording")
struct DeliveryWordingTests {
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
}
