import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// When DashPilot offers to record a lifecycle event the driver may have
/// missed, what it says about it, and everything it refuses to do.
///
/// The policy is exercised as plain values, because it is a pure function of a
/// delivery's recorded times and the instant it is asked about. The claims that
/// are about the **store** — that deriving a reminder writes nothing, and that
/// confirming one runs the ordinary lifecycle service — are driven against a
/// real container at the end.
///
/// Every date is an explicit offset from one fixed instant, so nothing here
/// depends on when it runs.
@MainActor
@Suite("Delivery progress assistance")
struct DeliveryProgressAssistanceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private let assistance = DeliveryProgressAssistance()

    /// Half an hour and a minute, which clears either threshold.
    private let stale: TimeInterval = 30 * 60 + 60

    private func delivery(
        number: Int = 1,
        id: UUID = UUID(),
        acceptedAt: Date,
        arrivedAtPickupAt: Date? = nil,
        pickedUpAt: Date? = nil,
        deliveredAt: Date? = nil,
        cancelledAt: Date? = nil
    ) -> AssistedDelivery {
        AssistedDelivery(
            id: id,
            number: number,
            record: DeliveryLifecycleRecord(
                acceptedAt: acceptedAt,
                arrivedAtPickupAt: arrivedAtPickupAt,
                pickedUpAt: pickedUpAt,
                deliveredAt: deliveredAt,
                cancelledAt: cancelledAt
            )
        )
    }

    // MARK: The state a reminder is offered in

    @Test("An accepted delivery that records no arrival is offered the arrival")
    func offersTheArrival() {
        let suggestion = assistance.suggestion(
            for: delivery(acceptedAt: at(0)),
            asOf: at(stale)
        )

        #expect(suggestion?.state == .accepted)
        #expect(suggestion?.action == .arriveAtPickup)
        #expect(suggestion?.action == DeliveryState.accepted.nextAction)
    }

    @Test("A delivery at its pickup that records no pickup is offered the pickup")
    func offersThePickup() {
        let suggestion = assistance.suggestion(
            for: delivery(acceptedAt: at(0), arrivedAtPickupAt: at(300)),
            asOf: at(300 + stale)
        )

        #expect(suggestion?.state == .arrivedAtPickup)
        #expect(suggestion?.action == .pickUp)
        #expect(suggestion?.action == DeliveryState.arrivedAtPickup.nextAction)
    }

    @Test("A delivery already in the car is never the subject of a reminder")
    func saysNothingAboutAPickedUpDelivery() {
        // Deliberate rather than incidental. With stacked orders, carrying one
        // for an hour while delivering another is ordinary work, so elapsed
        // time says least about a delivery exactly here.
        let suggestion = assistance.suggestion(
            for: delivery(acceptedAt: at(0), arrivedAtPickupAt: at(300), pickedUpAt: at(600)),
            asOf: at(600 + 8 * 3600)
        )

        #expect(suggestion == nil)
    }

    @Test("Nothing is offered before the threshold, on either side of it")
    func waitsForTheThreshold() {
        let accepted = delivery(acceptedAt: at(0))
        #expect(assistance.suggestion(for: accepted, asOf: at(30 * 60 - 1)) == nil)
        #expect(assistance.suggestion(for: accepted, asOf: at(30 * 60)) != nil)

        let waiting = delivery(acceptedAt: at(0), arrivedAtPickupAt: at(300))
        #expect(assistance.suggestion(for: waiting, asOf: at(300 + 30 * 60 - 1)) == nil)
        #expect(assistance.suggestion(for: waiting, asOf: at(300 + 30 * 60)) != nil)
    }

    @Test("The arrival threshold is measured from the arrival, not from the acceptance")
    func measuresFromTheLatestRecordedEvent() {
        // Accepted long ago and at the pickup a moment ago: the delivery is not
        // stale, and a rule measuring from acceptance would say it was.
        let suggestion = assistance.suggestion(
            for: delivery(acceptedAt: at(0), arrivedAtPickupAt: at(3 * 3600)),
            asOf: at(3 * 3600 + 60)
        )

        #expect(suggestion == nil)
    }

    // MARK: Terminal deliveries

    @Test("Nothing is offered after a terminal state", arguments: [true, false])
    func saysNothingAboutAFinishedDelivery(delivered: Bool) {
        let finished = delivery(
            acceptedAt: at(0),
            arrivedAtPickupAt: at(300),
            pickedUpAt: delivered ? at(600) : nil,
            deliveredAt: delivered ? at(900) : nil,
            cancelledAt: delivered ? nil : at(600)
        )

        #expect(assistance.suggestion(for: finished, asOf: at(900 + 8 * 3600)) == nil)
    }

    @Test("A delivery cancelled at its pickup is silent although its arrival is old")
    func saysNothingAboutACancellationFromThePickup() {
        // The shape that would slip through a rule reading only the latest
        // *active* stage: the arrival is hours old and there is no pickup.
        let cancelled = delivery(
            acceptedAt: at(0),
            arrivedAtPickupAt: at(300),
            cancelledAt: at(600)
        )

        #expect(assistance.suggestion(for: cancelled, asOf: at(300 + 8 * 3600)) == nil)
    }

    // MARK: Rows that are not evidence

    @Test("A row whose recorded times run backwards is not evidence")
    func saysNothingAboutAContradictoryRow() {
        let backwards = delivery(acceptedAt: at(600), arrivedAtPickupAt: at(300))

        #expect(backwards.record.isChronological == false)
        #expect(assistance.suggestion(for: backwards, asOf: at(600 + stale)) == nil)
    }

    @Test("A row recording a pickup with no arrival is not evidence")
    func saysNothingAboutAPickupWithNoArrival() {
        let anomalous = delivery(acceptedAt: at(0), pickedUpAt: at(600))

        #expect(anomalous.record.recordsPickupWithoutArrival)
        #expect(assistance.suggestion(for: anomalous, asOf: at(600 + stale)) == nil)
    }

    @Test("A delivery whose latest instant is in the future is not stale")
    func saysNothingAboutAFutureRow() {
        #expect(assistance.suggestion(for: delivery(acceptedAt: at(3600)), asOf: at(0)) == nil)
    }

    // MARK: Stacked deliveries

    @Test("Stacked deliveries are judged one at a time, each on its own record")
    func judgesEachDeliveryIndependently() {
        let stale = delivery(number: 1, acceptedAt: at(0))
        let fresh = delivery(number: 2, acceptedAt: at(3 * 3600))

        let suggestions = assistance.suggestions(among: [stale, fresh], asOf: at(3 * 3600 + 60))

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.number == 1)
        #expect(suggestions.first?.deliveryID == stale.id)
    }

    @Test("Two stale deliveries in different states are offered their own steps")
    func offersEachStackedDeliveryItsOwnStep() {
        let waiting = delivery(number: 1, acceptedAt: at(0), arrivedAtPickupAt: at(300))
        let heading = delivery(number: 2, acceptedAt: at(600))

        let suggestions = assistance.suggestions(among: [waiting, heading], asOf: at(600 + stale))

        #expect(suggestions.map(\.number) == [1, 2])
        #expect(suggestions.map(\.action) == [.pickUp, .arriveAtPickup])
        #expect(suggestions.map(\.deliveryID) == [waiting.id, heading.id])
    }

    @Test("A reminder never names a delivery other than the one it was derived from")
    func neverCrossesDeliveryIdentity() {
        let deliveries = (1...4).map { number in
            delivery(number: number, acceptedAt: at(TimeInterval(number) * 60))
        }

        let suggestions = assistance.suggestions(among: deliveries, asOf: at(4 * 60 + stale))

        #expect(suggestions.count == 4)
        for (suggestion, source) in zip(suggestions, deliveries) {
            #expect(suggestion.deliveryID == source.id)
            #expect(suggestion.number == source.number)
            #expect(suggestion.title == NumberedDelivery.title(number: source.number))
            #expect(suggestion.actionTitle.contains(suggestion.title))
            #expect(suggestion.spokenActionLabel.hasPrefix(suggestion.title))
            #expect(suggestion.spokenDismissLabel.contains(suggestion.title))
            #expect(suggestion.spokenEvidenceStatement.hasPrefix(suggestion.title))
        }
    }

    @Test("Nothing is offered for an empty set of deliveries")
    func offersNothingForNoDeliveries() {
        #expect(assistance.suggestions(among: [], asOf: at(stale)).isEmpty)
    }

    // MARK: What it says, and what it must never say

    @Test("The evidence is a statement about the record and carries the duration")
    func statesTheEvidence() {
        let accepted = assistance.suggestion(for: delivery(acceptedAt: at(0)), asOf: at(45 * 60))
        #expect(accepted?.stillRecordingNothingNewerFor == TimeInterval(45 * 60))
        #expect(accepted?.evidenceStatement == "Accepted 45 min ago · no arrival recorded")
        #expect(accepted?.question == "Already at the pickup?")

        let waiting = assistance.suggestion(
            for: delivery(acceptedAt: at(0), arrivedAtPickupAt: at(0)),
            asOf: at(45 * 60)
        )
        #expect(waiting?.evidenceStatement == "At the pickup 45 min ago · no pickup recorded")
        #expect(waiting?.question == "Already picked this order up?")
    }

    @Test("Every sentence is a question or a record, and none of them claims an observation")
    func claimsNothingItCannotSee() {
        // The words this feature exists not to print. A reminder that says
        // "you arrived" teaches a driver that DashPilot knows where they are,
        // which is the belief that costs them the day it is wrong.
        let forbidden = [
            "you arrived",
            "you picked up",
            "we detected",
            "detected",
            "we noticed",
            "confirmed",
            "you are at",
            "you have arrived",
            "looks like you"
        ]

        let suggestions = [
            assistance.suggestion(for: delivery(acceptedAt: at(0)), asOf: at(stale)),
            assistance.suggestion(
                for: delivery(acceptedAt: at(0), arrivedAtPickupAt: at(60)),
                asOf: at(60 + stale)
            )
        ].compactMap { $0 }

        #expect(suggestions.count == 2)
        for suggestion in suggestions {
            let sentences = [
                suggestion.evidenceStatement,
                suggestion.spokenEvidenceStatement,
                suggestion.question,
                suggestion.actionTitle,
                suggestion.spokenActionLabel,
                suggestion.dismissTitle,
                suggestion.spokenDismissLabel,
                suggestion.spokenLabel
            ]
            for sentence in sentences {
                let lowered = sentence.lowercased()
                for word in forbidden {
                    #expect(!lowered.contains(word), "\"\(sentence)\" claims \"\(word)\"")
                }
            }
        }
    }

    @Test("The caveat travels with every reminder, spoken and printed")
    func alwaysCarriesTheCaveat() {
        let suggestion = try? #require(assistance.suggestion(for: delivery(acceptedAt: at(0)), asOf: at(stale)))

        #expect(DeliveryProgressSuggestion.uncertaintyStatement.contains("cannot tell where you are"))
        #expect(suggestion?.spokenLabel.contains(DeliveryProgressSuggestion.uncertaintyStatement) == true)
    }

    @Test("The offered action is always the delivery's own next step")
    func neverOffersAnInvalidNextAction() {
        for state in DeliveryState.allCases {
            let record: AssistedDelivery
            switch state {
            case .accepted:
                record = delivery(acceptedAt: at(0))
            case .arrivedAtPickup:
                record = delivery(acceptedAt: at(0), arrivedAtPickupAt: at(60))
            case .pickedUp:
                record = delivery(acceptedAt: at(0), arrivedAtPickupAt: at(60), pickedUpAt: at(120))
            case .delivered:
                record = delivery(
                    acceptedAt: at(0),
                    arrivedAtPickupAt: at(60),
                    pickedUpAt: at(120),
                    deliveredAt: at(180)
                )
            case .cancelled:
                record = delivery(acceptedAt: at(0), cancelledAt: at(60))
            }

            #expect(record.record.state == state)

            guard let suggestion = assistance.suggestion(for: record, asOf: at(180 + 8 * 3600)) else { continue }
            #expect(suggestion.action == state.nextAction)
            #expect(state == .accepted || state == .arrivedAtPickup)
        }
    }

    // MARK: Against a real store

    @Test("Deriving a reminder changes no delivery and writes nothing")
    func mutatesNothing() throws {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(delivery, at: at(120))

        let before = DeliveryLifecycleRecord(delivery)

        let suggestions = DeliveryProgressAssistance().suggestions(
            among: shift.numberedActiveDeliveries.map(AssistedDelivery.init),
            asOf: at(120 + stale)
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.action == .pickUp)
        // The reminder exists and the delivery has not moved: same state, same
        // instants, and nothing pending in the context.
        #expect(DeliveryLifecycleRecord(delivery) == before)
        #expect(delivery.state == .arrivedAtPickup)
        #expect(context.hasChanges == false)
    }

    @Test("Confirming a reminder runs the ordinary lifecycle action and moves only that delivery")
    func confirmingRunsTheExistingLifecycleAction() throws {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let shift = try ShiftService(context: context).startShift(at: start)
        let deliveries = DeliveryService(context: context)

        let waiting = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(waiting, at: at(120))
        let heading = try deliveries.startDelivery(at: at(180))

        let suggestions = DeliveryProgressAssistance().suggestions(
            among: shift.numberedActiveDeliveries.map(AssistedDelivery.init),
            asOf: at(180 + stale)
        )
        #expect(suggestions.count == 2)

        // The panel resolves a reminder to the delivery with its identity and
        // then takes that delivery's own next step, which is exactly this.
        let suggestion = try #require(suggestions.first { $0.deliveryID == waiting.id })
        let target = try #require(shift.deliveries.first { $0.id == suggestion.deliveryID })
        #expect(suggestion.action == .pickUp)
        try deliveries.markPickedUp(target, at: at(180 + stale))

        #expect(waiting.state == .pickedUp)
        #expect(waiting.pickedUpAt == at(180 + stale))
        // The sibling is untouched, which is what "a reminder does not cross
        // delivery identity" means once a write is involved.
        #expect(heading.state == .accepted)
        #expect(heading.arrivedAtPickupAt == nil)
    }

    @Test("A finished shift's deliveries are offered nothing, so no history is ever the subject")
    func saysNothingAboutHistory() throws {
        let context = try ModelContext(ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let deliveries = DeliveryService(context: context)

        let delivery = try deliveries.startDelivery(at: at(60))
        try deliveries.markArrivedAtPickup(delivery, at: at(120))
        try deliveries.markPickedUp(delivery, at: at(180))
        try deliveries.markDelivered(delivery, at: at(240))
        try shifts.endActiveShift(at: at(300))

        // Every delivery a finished shift holds is terminal, because a shift
        // cannot end with one open. Asked anyway, days later, the policy is
        // silent, so there is no path by which a historical timestamp is
        // offered for correction here.
        let suggestions = DeliveryProgressAssistance().suggestions(
            among: shift.numberedDeliveries.map(AssistedDelivery.init),
            asOf: at(300 + 48 * 3600)
        )

        #expect(suggestions.isEmpty)
    }
}
