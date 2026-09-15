import Foundation
import Testing
@testable import DashPilot

/// Correcting a historical `Delivered` into the cancellation it was: which
/// instant the correction writes, which rows it refuses, and what the model
/// leaves untouched.
///
/// The rule is exercised as plain values first, because several of the rows it
/// has to judge are ones the lifecycle refuses to produce. What the model can
/// actually be driven into is exercised on a real `Delivery` below, and what the
/// store does with it is in `HistoricalDeliveryCancellationServiceTests`.
///
/// Every date is an explicit offset from one fixed instant, so nothing here
/// depends on when it runs.
@MainActor
@Suite("Historical delivery cancellation")
struct HistoricalDeliveryCancellationTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A delivery driven through the lifecycle to delivered, without a store.
    private func makeDeliveredDelivery() throws -> Delivery {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.markPickedUp(at: at(900))
        try delivery.markDelivered(at: at(1500))
        return delivery
    }

    // MARK: The instant the correction writes

    /// The whole of the timestamp decision, and the one assertion every figure
    /// downstream depends on.
    @Test("The recorded completion becomes the cancellation, to the instant")
    func reusesTheRecordedCompletion() throws {
        let correction = try HistoricalDeliveryCancellation(
            correcting: DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                pickedUpAt: at(900),
                deliveredAt: at(1500)
            )
        )

        #expect(correction.cancelledAt == at(1500))
    }

    @Test("A completion recorded straight from an arrival is corrected too")
    func correctsACompletionWithoutAPickup() throws {
        // Unreachable through the app, which refuses a completion before a
        // pickup. It is corrected rather than refused because the state it lands
        // in is `cancelled`, which the lifecycle reaches from every active state
        // including this one.
        let correction = try HistoricalDeliveryCancellation(
            correcting: DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                deliveredAt: at(1500)
            )
        )

        #expect(correction.cancelledAt == at(1500))
    }

    @Test("A completion recorded straight from the acceptance is corrected too")
    func correctsACompletionWithoutAnArrival() throws {
        let correction = try HistoricalDeliveryCancellation(
            correcting: DeliveryLifecycleRecord(acceptedAt: at(300), deliveredAt: at(1500))
        )

        #expect(correction.cancelledAt == at(1500))
    }

    @Test("A completion recorded in the same instant as the acceptance is still a recorded instant")
    func correctsAZeroLengthLifecycle() throws {
        let correction = try HistoricalDeliveryCancellation(
            correcting: DeliveryLifecycleRecord(acceptedAt: at(300), deliveredAt: at(300))
        )

        #expect(correction.cancelledAt == at(300))
    }

    // MARK: What is refused

    @Test("A delivery still in progress has no completion to correct")
    func refusesAnActiveDelivery() {
        for record in [
            DeliveryLifecycleRecord(acceptedAt: at(300)),
            DeliveryLifecycleRecord(acceptedAt: at(300), arrivedAtPickupAt: at(600)),
            DeliveryLifecycleRecord(acceptedAt: at(300), arrivedAtPickupAt: at(600), pickedUpAt: at(900))
        ] {
            #expect(throws: HistoricalCancellationRefusal.notDelivered) {
                try HistoricalDeliveryCancellation(correcting: record)
            }
        }
    }

    /// What a second invocation meets, and what makes a double tap safe.
    @Test("A delivery already recorded as cancelled is refused")
    func refusesACancelledDelivery() {
        #expect(throws: HistoricalCancellationRefusal.alreadyCancelled) {
            try HistoricalDeliveryCancellation(
                correcting: DeliveryLifecycleRecord(
                    acceptedAt: at(300),
                    arrivedAtPickupAt: at(600),
                    cancelledAt: at(1500)
                )
            )
        }
    }

    /// The row a correction that already succeeded leaves behind, asked again.
    @Test("Correcting the same record twice is refused the second time")
    func refusesASecondCorrection() throws {
        let delivered = DeliveryLifecycleRecord(
            acceptedAt: at(300),
            arrivedAtPickupAt: at(600),
            pickedUpAt: at(900),
            deliveredAt: at(1500)
        )
        let first = try HistoricalDeliveryCancellation(correcting: delivered)

        let corrected = DeliveryLifecycleRecord(
            acceptedAt: delivered.acceptedAt,
            arrivedAtPickupAt: delivered.arrivedAtPickupAt,
            pickedUpAt: delivered.pickedUpAt,
            deliveredAt: nil,
            cancelledAt: first.cancelledAt
        )

        #expect(throws: HistoricalCancellationRefusal.alreadyCancelled) {
            try HistoricalDeliveryCancellation(correcting: corrected)
        }
    }

    @Test("A pickup with no arrival before it is refused rather than repaired")
    func refusesAPickupWithoutAnArrival() {
        #expect(throws: HistoricalCancellationRefusal.pickedUpWithoutArrival) {
            try HistoricalDeliveryCancellation(
                correcting: DeliveryLifecycleRecord(
                    acceptedAt: at(300),
                    pickedUpAt: at(900),
                    deliveredAt: at(1500)
                )
            )
        }
    }

    @Test("Times that run backwards are refused, and the pair is not blessed")
    func refusesContradictoryTimestamps() {
        let contradictions = [
            // The arrival precedes the acceptance.
            DeliveryLifecycleRecord(acceptedAt: at(600), arrivedAtPickupAt: at(300), deliveredAt: at(1500)),
            // The pickup precedes the arrival.
            DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(900),
                pickedUpAt: at(600),
                deliveredAt: at(1500)
            ),
            // The completion precedes the pickup, which is the instant the
            // correction would otherwise reuse.
            DeliveryLifecycleRecord(
                acceptedAt: at(300),
                arrivedAtPickupAt: at(600),
                pickedUpAt: at(1500),
                deliveredAt: at(900)
            ),
            // The completion precedes the acceptance.
            DeliveryLifecycleRecord(acceptedAt: at(1500), deliveredAt: at(300))
        ]

        for record in contradictions {
            #expect(throws: HistoricalCancellationRefusal.timestampsOutOfOrder) {
                try HistoricalDeliveryCancellation(correcting: record)
            }
        }
    }

    @Test("Every refusal is reachable, so none is decoration")
    func everyRefusalIsReachable() {
        var met: Set<HistoricalCancellationRefusal> = []
        let rows = [
            DeliveryLifecycleRecord(acceptedAt: at(300)),
            DeliveryLifecycleRecord(acceptedAt: at(300), cancelledAt: at(1500)),
            DeliveryLifecycleRecord(acceptedAt: at(300), pickedUpAt: at(900), deliveredAt: at(1500)),
            DeliveryLifecycleRecord(acceptedAt: at(1500), deliveredAt: at(300))
        ]

        for record in rows {
            do {
                _ = try HistoricalDeliveryCancellation(correcting: record)
            } catch let refusal as HistoricalCancellationRefusal {
                met.insert(refusal)
            } catch {
                Issue.record("An unexpected error: \(error)")
            }
        }

        #expect(met == Set(HistoricalCancellationRefusal.allCases))
    }

    // MARK: The model applies it

    @Test("The model moves one timestamp to the other and leaves the rest byte for byte")
    func theModelCorrectsOneDelivery() throws {
        let delivery = try makeDeliveredDelivery()

        try delivery.correctCompletionToCancellation()

        #expect(delivery.state == .cancelled)
        #expect(delivery.deliveredAt == nil)
        #expect(delivery.cancelledAt == at(1500))
        // The events before the ending, asserted as values rather than as
        // presence: a correction that shifted one of them by a second would be
        // invisible to a nil check.
        #expect(delivery.acceptedAt == at(300))
        #expect(delivery.arrivedAtPickupAt == at(600))
        #expect(delivery.pickedUpAt == at(900))
    }

    @Test("The corrected delivery is still terminal and still has an ending to measure to")
    func theCorrectedDeliveryStaysTerminal() throws {
        let delivery = try makeDeliveredDelivery()
        let before = DeliveryActiveInterval(delivery)

        try delivery.correctCompletionToCancellation()

        #expect(delivery.state.isFinished)
        #expect(delivery.isActive == false)
        #expect(DeliveryActiveInterval(delivery) == before)
        #expect(DeliveryActiveInterval(delivery).isUnfinished == false)
        #expect(DeliveryActiveInterval(delivery).bounds == at(300)...at(1500))
    }

    @Test("The recorded pickup wait is untouched")
    func theRecordedWaitSurvives() throws {
        let delivery = try makeDeliveredDelivery()
        let wait = try #require(delivery.pickupWait)

        try delivery.correctCompletionToCancellation()

        #expect(delivery.pickupWait == wait)
        #expect(delivery.pickupWait == 300)
    }

    /// The one derived figure that is deliberately lost, because its definition
    /// requires a completion this delivery no longer records.
    @Test("The delivery's own completed duration and hourly figure go, by their own definitions")
    func theCompletedDurationGoes() throws {
        let delivery = try makeDeliveredDelivery()
        try delivery.setGrossEarnings(Money(minorUnits: 1_200))
        #expect(delivery.completedDuration == 1_200)
        #expect(delivery.effectiveEarningsPerDeliveryHour.amount != nil)

        try delivery.correctCompletionToCancellation()

        #expect(delivery.completedDuration == nil)
        #expect(delivery.effectiveEarningsPerDeliveryHour == .unavailable(.deliveryNotCompleted))
    }

    @Test("A recorded gross amount stays recorded, and so does an expectation")
    func theMoneyIsPreserved() throws {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.setExpectedEarnings(Money(minorUnits: 850))
        try delivery.markPickedUp(at: at(900))
        try delivery.markDelivered(at: at(1500))
        try delivery.setGrossEarnings(Money(minorUnits: 1_275))

        try delivery.correctCompletionToCancellation()

        // Neither amount is deleted, converted or moved into the other. A
        // cancelled delivery may truthfully carry a gross amount, which is what
        // `setGrossEarnings` already allows.
        #expect(delivery.grossEarnings == Money(minorUnits: 1_275))
        #expect(delivery.expectedEarnings == Money(minorUnits: 850))
    }

    @Test("A corrected delivery can still be given an amount, because it is finished")
    func theCorrectedDeliveryStillAcceptsAnAmount() throws {
        let delivery = try makeDeliveredDelivery()

        try delivery.correctCompletionToCancellation()
        try delivery.setGrossEarnings(Money(minorUnits: 300))

        #expect(delivery.grossEarnings == Money(minorUnits: 300))
    }

    @Test("The pickup place is untouched")
    func thePickupPlaceSurvives() throws {
        let delivery = try makeDeliveredDelivery()
        let place = try PickupPlace(name: PickupPlaceName("Corner Noodle Bar"), createdAt: at(0))
        delivery.setPickupPlace(place)

        try delivery.correctCompletionToCancellation()

        #expect(delivery.pickupPlace === place)
    }

    @Test("The model refuses a second correction and writes nothing")
    func theModelRefusesASecondCorrection() throws {
        let delivery = try makeDeliveredDelivery()
        try delivery.correctCompletionToCancellation()

        #expect(throws: HistoricalCancellationRefusal.alreadyCancelled) {
            try delivery.correctCompletionToCancellation()
        }
        #expect(delivery.cancelledAt == at(1500))
        #expect(delivery.deliveredAt == nil)
    }

    @Test("A delivery cancelled in the ordinary way is refused and does not move")
    func theModelRefusesAnOrdinaryCancellation() throws {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.cancel(at: at(1_000))

        #expect(throws: HistoricalCancellationRefusal.alreadyCancelled) {
            try delivery.correctCompletionToCancellation()
        }
        #expect(delivery.cancelledAt == at(1_000))
    }

    @Test("A delivery still in progress is refused and keeps every timestamp it had")
    func theModelRefusesAnActiveDelivery() throws {
        let delivery = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        try delivery.markArrivedAtPickup(at: at(600))

        #expect(throws: HistoricalCancellationRefusal.notDelivered) {
            try delivery.correctCompletionToCancellation()
        }
        #expect(delivery.state == .arrivedAtPickup)
        #expect(delivery.arrivedAtPickupAt == at(600))
        #expect(delivery.cancelledAt == nil)
    }

    /// The correction is a correction, not a second way to cancel: it cannot be
    /// used to end work that is still running, and `cancel(at:)` cannot be used
    /// to rewrite a completion.
    @Test("The two entry points do not overlap")
    func correctionAndCancellationStayApart() throws {
        let delivered = try makeDeliveredDelivery()
        #expect(throws: DeliveryError.alreadyFinished(.delivered)) {
            try delivered.cancel(at: at(1_800))
        }

        let active = Delivery(shift: Shift(startedAt: start), acceptedAt: at(300))
        #expect(throws: HistoricalCancellationRefusal.notDelivered) {
            try active.correctCompletionToCancellation()
        }
    }

    // MARK: An offer reads its deliveries again

    @Test("An offer of one becomes cancelled")
    func aSoleDeliveryMakesTheOfferCancelled() throws {
        let shift = Shift(startedAt: start)
        let (offer, deliveries) = try shift.beginOffer(deliveryCount: 1, at: at(300))
        let delivery = try #require(deliveries.first)
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.markPickedUp(at: at(900))
        try delivery.markDelivered(at: at(1500))
        #expect(offer.state == .completed)

        try delivery.correctCompletionToCancellation()

        #expect(offer.state == .cancelled)
        #expect(offer.state.isTerminal)
        #expect(offer.state.historyDescription == "All deliveries cancelled")
    }

    @Test("An offer of two with one corrected becomes partly completed, and the sibling does not move")
    func oneOfTwoMakesTheOfferPartlyCompleted() throws {
        let shift = Shift(startedAt: start)
        let (offer, deliveries) = try shift.beginOffer(deliveryCount: 2, at: at(300))
        for (index, delivery) in deliveries.enumerated() {
            let step = TimeInterval(index) * 60
            try delivery.markArrivedAtPickup(at: at(600 + step))
            try delivery.markPickedUp(at: at(900 + step))
            try delivery.markDelivered(at: at(1500 + step))
        }
        #expect(offer.state == .completed)
        let sibling = try #require(deliveries.last)

        try #require(deliveries.first).correctCompletionToCancellation()

        #expect(offer.state == .partiallyCompleted)
        #expect(offer.state.isTerminal)
        #expect(offer.state.historyDescription == "Partly completed, partly cancelled")
        // Membership and the sibling are both untouched: the correction reads
        // one delivery and writes one delivery.
        #expect(offer.deliveries.count == 2)
        #expect(sibling.state == .delivered)
        #expect(sibling.deliveredAt == at(1560))
        #expect(sibling.offer === offer)
    }

    @Test("Correcting both deliveries of an offer makes it cancelled")
    func bothOfTwoMakeTheOfferCancelled() throws {
        let shift = Shift(startedAt: start)
        let (offer, deliveries) = try shift.beginOffer(deliveryCount: 2, at: at(300))
        for (index, delivery) in deliveries.enumerated() {
            let step = TimeInterval(index) * 60
            try delivery.markArrivedAtPickup(at: at(600 + step))
            try delivery.markPickedUp(at: at(900 + step))
            try delivery.markDelivered(at: at(1500 + step))
            try delivery.correctCompletionToCancellation()
        }

        #expect(offer.state == .cancelled)
    }

    @Test("The offer's own acceptance time never moves")
    func theOffersAcceptanceIsUntouched() throws {
        let shift = Shift(startedAt: start)
        let (offer, deliveries) = try shift.beginOffer(deliveryCount: 1, at: at(300))
        let delivery = try #require(deliveries.first)
        try delivery.markArrivedAtPickup(at: at(600))
        try delivery.markPickedUp(at: at(900))
        try delivery.markDelivered(at: at(1500))

        try delivery.correctCompletionToCancellation()

        #expect(offer.acceptedAt == at(300))
        #expect(shift.offers.count == 1)
    }

    // MARK: The shift's own counts

    @Test("The shift counts a cancellation where it counted a completion, and nothing in progress")
    func theShiftRecountsItsDeliveries() throws {
        let shift = Shift(startedAt: start)
        let (_, deliveries) = try shift.beginOffer(deliveryCount: 2, at: at(300))
        for (index, delivery) in deliveries.enumerated() {
            let step = TimeInterval(index) * 60
            try delivery.markArrivedAtPickup(at: at(600 + step))
            try delivery.markPickedUp(at: at(900 + step))
            try delivery.markDelivered(at: at(1500 + step))
        }
        #expect(shift.deliverySummary == DeliverySummary(completed: 2, cancelled: 0))

        try #require(deliveries.first).correctCompletionToCancellation()

        #expect(shift.deliverySummary == DeliverySummary(completed: 1, cancelled: 1))
        // The count that matters most: a historical correction must never put
        // work back in progress inside a shift that has finished.
        #expect(shift.deliverySummary.inProgress == 0)
        #expect(shift.deliverySummary.recorded == 2)
        #expect(shift.activeDeliveries.isEmpty)
        #expect(shift.deliverySummary.statement == "1 delivery completed · 1 cancelled")
    }

    @Test("The shift's delivery active time is unchanged to the second")
    func theActiveTimeUnionIsUnchanged() throws {
        let shift = Shift(startedAt: start)
        let (_, deliveries) = try shift.beginOffer(deliveryCount: 2, at: at(300))
        // Deliberately overlapping, so the union is doing work rather than
        // adding two disjoint intervals.
        for (index, delivery) in deliveries.enumerated() {
            let step = TimeInterval(index) * 120
            try delivery.markArrivedAtPickup(at: at(600 + step))
            try delivery.markPickedUp(at: at(900 + step))
            try delivery.markDelivered(at: at(1500 + step))
        }
        try shift.end(at: at(7_200))
        let before = shift.deliveryActiveTime()

        try #require(deliveries.first).correctCompletionToCancellation()

        #expect(shift.deliveryActiveTime() == before)
        #expect(shift.deliveryActiveTime().duration == 1_320)
        #expect(shift.deliveryActiveTime().unfinishedIntervalCount == 0)
        // And the shift itself has not moved either.
        #expect(shift.endedAt == at(7_200))
        #expect(shift.completedWorkingDuration == 7_200)
    }

    // MARK: The sentences a driver is asked to agree to

    @Test("The prompt names the delivery in all three of its parts")
    func thePromptNamesItsSubject() {
        let numbered = NumberedDelivery(number: 2, delivery: Delivery(shift: Shift(startedAt: start), acceptedAt: at(300)))
        let prompt = HistoricalCancellationPrompt.correct(numbered, keepsRecordedMoney: false)

        #expect(prompt.title == "Correct Delivery 2 to Cancelled?")
        #expect(prompt.detail.contains("Delivery 2"))
        #expect(prompt.confirmTitle == "Correct Delivery 2")
    }

    @Test("The prompt states the three facts the correction turns on")
    func thePromptStatesTheConsequences() {
        let numbered = NumberedDelivery(number: 1, delivery: Delivery(shift: Shift(startedAt: start), acceptedAt: at(300)))
        let prompt = HistoricalCancellationPrompt.correct(numbered, keepsRecordedMoney: false)

        // It stays terminal.
        #expect(prompt.detail.contains("stays a finished delivery"))
        // What it becomes.
        #expect(prompt.detail.contains("recorded as cancelled instead of delivered"))
        // Where the cancellation time comes from.
        #expect(prompt.detail.contains("the time you recorded it as delivered becomes the time it was cancelled"))
        // What is left alone.
        #expect(prompt.detail.contains(HistoricalCancellationPrompt.unchangedStatement))
    }

    /// The sentence covers every kind of money the delivery may hold — the
    /// platform amount, an additional tip, or both — because a correction that
    /// preserved one and not the other would be a different promise.
    @Test("The money sentence appears only where there is money")
    func thePromptNamesEarningsOnlyWhereThereAreSome() {
        let numbered = NumberedDelivery(number: 1, delivery: Delivery(shift: Shift(startedAt: start), acceptedAt: at(300)))

        let withMoney = HistoricalCancellationPrompt.correct(numbered, keepsRecordedMoney: true)
        let without = HistoricalCancellationPrompt.correct(numbered, keepsRecordedMoney: false)

        #expect(withMoney.detail.contains("Everything you recorded it as paying, tips included, stays recorded"))
        #expect(without.detail.contains("stays recorded") == false)
        #expect(without.detail.contains("tips") == false)
    }

    /// The rule the recovery screen already keeps, applied to a second
    /// correction: nothing here is an editor, and nothing says it is.
    @Test("Nothing in the wording says Edit, and nothing carries a figure")
    func theWordingPromisesNoEditor() {
        let numbered = NumberedDelivery(number: 1, delivery: Delivery(shift: Shift(startedAt: start), acceptedAt: at(300)))
        let prompt = HistoricalCancellationPrompt.correct(numbered, keepsRecordedMoney: true)
        let sentences = [
            prompt.title,
            prompt.detail,
            prompt.confirmTitle,
            NumberedDelivery.correctToCancelledActionTitle,
            numbered.spokenCorrectToCancelledLabel
        ]

        for sentence in sentences {
            #expect(sentence.lowercased().contains("edit") == false, "Not an editor: \(sentence)")
            #expect(sentence.contains("$") == false, "No amount: \(sentence)")
            #expect(sentence.contains(String(describing: numbered.delivery.id)) == false)
        }
    }

    @Test("The control says it is correcting a record rather than ending live work")
    func theControlSaysWhatItIs() {
        let numbered = NumberedDelivery(number: 3, delivery: Delivery(shift: Shift(startedAt: start), acceptedAt: at(300)))

        #expect(NumberedDelivery.correctToCancelledActionTitle == "Correct to Cancelled")
        // The printed title is short because it sits in a half-width cell under
        // a card that has already named itself; the spoken one names the
        // subject, because a listener has no card in view to refer back to.
        #expect(numbered.spokenCorrectToCancelledLabel.hasPrefix("Correct Delivery 3 to cancelled."))
        #expect(numbered.spokenCorrectToCancelledLabel.contains("stays a finished delivery"))
        #expect(numbered.spokenCorrectToCancelledLabel.contains("cancelled instead of delivered"))
    }
}
