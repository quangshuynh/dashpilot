import Foundation
import Testing
@testable import DashPilot

/// The rule that decides which recorded lifecycle times a finished delivery may
/// be corrected to, tested as the plain value it is: no store, no container, no
/// rendered view.
///
/// ## What is being asserted here
///
/// Three kinds of claim. First, that every refusal is a refusal: nothing is
/// clamped, swapped or nudged into an acceptable instant, and above all nothing
/// **cascades** — a completion dragged behind its own pickup is refused naming
/// the pickup rather than dragging the pickup with it. Second, that a stage the
/// delivery never recorded is never brought into existence and a stage it does
/// record is never taken away. Third, that a refusal says which recorded fact it
/// collided with, because that is the whole of what a driver needs in order to
/// correct it.
///
/// Every timestamp here is invented.
@Suite("Delivery time correction")
struct DeliveryTimeCorrectionTests {
    private let shiftStart = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { shiftStart.addingTimeInterval(minutes * 60) }

    /// A four-hour completed shift, which is the window every case below is
    /// judged inside.
    private var shiftWindow: ClosedRange<Date> { shiftStart...at(240) }

    /// A delivery accepted at 60, arriving at 70, collected at 80 and delivered
    /// at 120: the ordinary shape, with every stage recorded.
    private var delivered: DeliveryLifecycleRecord {
        DeliveryLifecycleRecord(
            acceptedAt: at(60),
            arrivedAtPickupAt: at(70),
            pickedUpAt: at(80),
            deliveredAt: at(120)
        )
    }

    /// The same delivery cancelled at the counter: an arrival, no pickup, and a
    /// cancellation.
    private var cancelledAtPickup: DeliveryLifecycleRecord {
        DeliveryLifecycleRecord(
            acceptedAt: at(60),
            arrivedAtPickupAt: at(70),
            cancelledAt: at(95)
        )
    }

    private func correction(
        _ recorded: DeliveryLifecycleRecord,
        to proposed: DeliveryLifecycleRecord,
        within window: ClosedRange<Date>? = nil
    ) throws -> DeliveryTimeCorrection {
        try DeliveryTimeCorrection(
            correcting: recorded,
            to: proposed,
            within: window ?? shiftWindow
        )
    }

    private func refusal(
        _ recorded: DeliveryLifecycleRecord,
        to proposed: DeliveryLifecycleRecord,
        within window: ClosedRange<Date>? = nil
    ) -> DeliveryTimeCorrectionRefusal? {
        do {
            _ = try correction(recorded, to: proposed, within: window)
            return nil
        } catch let error as DeliveryTimeCorrectionRefusal {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    // MARK: Correcting one stage at a time

    @Test("A completion recorded late is corrected to the instant it really happened")
    func aLateCompletionIsCorrectedEarlier() throws {
        let proposed = delivered.replacing(.delivered, with: at(95))
        let correction = try correction(delivered, to: proposed)

        #expect(correction.corrected.deliveredAt == at(95))
        #expect(correction.movedEvents == [.delivered], "One stage moved, and only one")
        #expect(correction.recorded.deliveredAt == at(120), "The record it was judged against is carried")
    }

    @Test("Acceptance is correctable, and moving it moves nothing else")
    func acceptanceIsCorrectable() throws {
        let correction = try correction(delivered, to: delivered.replacing(.accepted, with: at(50)))

        #expect(correction.corrected.acceptedAt == at(50))
        #expect(correction.corrected.arrivedAtPickupAt == delivered.arrivedAtPickupAt)
        #expect(correction.corrected.pickedUpAt == delivered.pickedUpAt)
        #expect(correction.corrected.deliveredAt == delivered.deliveredAt)
        #expect(correction.movedEvents == [.accepted])
    }

    @Test("The arrival at the pickup is correctable")
    func arrivalIsCorrectable() throws {
        let correction = try correction(delivered, to: delivered.replacing(.arrivedAtPickup, with: at(75)))

        #expect(correction.corrected.arrivedAtPickupAt == at(75))
        #expect(correction.movedEvents == [.arrivedAtPickup])
    }

    @Test("The pickup is correctable")
    func pickupIsCorrectable() throws {
        let correction = try correction(delivered, to: delivered.replacing(.pickedUp, with: at(78)))

        #expect(correction.corrected.pickedUpAt == at(78))
        #expect(correction.movedEvents == [.pickedUp])
    }

    @Test("Several stages may be corrected in one proposal, and all of them are judged together")
    func severalStagesMoveInOneProposal() throws {
        let proposed = delivered
            .replacing(.pickedUp, with: at(85))
            .replacing(.delivered, with: at(100))
        let correction = try correction(delivered, to: proposed)

        #expect(correction.movedEvents == [.pickedUp, .delivered], "In lifecycle order")
        #expect(correction.corrected.pickedUpAt == at(85))
        #expect(correction.corrected.deliveredAt == at(100))
    }

    @Test("Re-recording the times a delivery already has is accepted and moves nothing")
    func aNoOpCorrectionIsAccepted() throws {
        let correction = try correction(delivered, to: delivered)

        #expect(correction.changesNothing)
        #expect(correction.movedEvents.isEmpty)
        #expect(correction.corrected == delivered)
    }

    // MARK: What a correction derives

    @Test("A corrected completion changes the delivery's completed duration")
    func completedDurationFollowsTheCorrection() throws {
        #expect(delivered.completedDuration == 3_600, "An hour as recorded")

        let correction = try correction(delivered, to: delivered.replacing(.delivered, with: at(90)))

        #expect(correction.corrected.completedDuration == 1_800, "and half an hour once corrected")
    }

    @Test("A corrected pickup changes the recorded pickup wait, and nothing else touches it")
    func pickupWaitFollowsTheCorrection() throws {
        #expect(delivered.pickupWait == 600, "Ten minutes as recorded")

        let laterPickup = try correction(delivered, to: delivered.replacing(.pickedUp, with: at(90)))
        #expect(laterPickup.corrected.pickupWait == 1_200, "Twenty once the pickup moves")

        let laterCompletion = try correction(delivered, to: delivered.replacing(.delivered, with: at(200)))
        #expect(laterCompletion.corrected.pickupWait == 600, "and a completion moving leaves the wait alone")
    }

    @Test("A delivery with no recorded pickup has no wait before or after a correction")
    func anAbsentPickupHasNoWait() throws {
        #expect(cancelledAtPickup.pickupWait == nil)

        let proposed = cancelledAtPickup.replacing(.arrivedAtPickup, with: at(65))
        let correction = try correction(cancelledAtPickup, to: proposed)

        #expect(correction.corrected.pickupWait == nil, "Correcting the arrival does not invent the other end")
    }

    @Test("A cancelled delivery has no completed duration, corrected or not")
    func aCancelledDeliveryHasNoCompletedDuration() throws {
        #expect(cancelledAtPickup.completedDuration == nil)

        let correction = try correction(cancelledAtPickup, to: cancelledAtPickup.replacing(.cancelled, with: at(80)))

        #expect(correction.corrected.completedDuration == nil)
    }

    // MARK: Ordering

    @Test("A completion moved behind its own pickup is refused, naming the pickup")
    func aCompletionCannotPrecedeItsPickup() {
        #expect(
            refusal(delivered, to: delivered.replacing(.delivered, with: at(75)))
                == .outOfOrder(event: .delivered, mustNotPrecede: .pickedUp),
            "and the pickup is named rather than moved out of the way"
        )
    }

    @Test("A pickup moved behind its own arrival is refused, naming the arrival")
    func aPickupCannotPrecedeItsArrival() {
        #expect(
            refusal(delivered, to: delivered.replacing(.pickedUp, with: at(65)))
                == .outOfOrder(event: .pickedUp, mustNotPrecede: .arrivedAtPickup)
        )
    }

    @Test("An arrival moved behind the acceptance is refused, naming the acceptance")
    func anArrivalCannotPrecedeAcceptance() {
        #expect(
            refusal(delivered, to: delivered.replacing(.arrivedAtPickup, with: at(55)))
                == .outOfOrder(event: .arrivedAtPickup, mustNotPrecede: .accepted)
        )
    }

    @Test("Acceptance moved past the rest of the lifecycle is refused, naming the arrival it would pass")
    func acceptanceCannotOvertakeTheRest() {
        #expect(
            refusal(delivered, to: delivered.replacing(.accepted, with: at(100)))
                == .outOfOrder(event: .arrivedAtPickup, mustNotPrecede: .accepted)
        )
    }

    @Test("The conflicting fact is corrected explicitly, and then the whole proposal is accepted")
    func correctingTheConflictingFactResolvesIt() throws {
        let tooEarly = delivered.replacing(.delivered, with: at(75))
        #expect(refusal(delivered, to: tooEarly) != nil, "Refused on its own")

        let both = tooEarly.replacing(.pickedUp, with: at(72))
        let correction = try correction(delivered, to: both)

        #expect(correction.corrected.pickedUpAt == at(72))
        #expect(correction.corrected.deliveredAt == at(75))
    }

    @Test("Touching instants are in order, because two events can share a minute")
    func touchingInstantsAreAccepted() {
        #expect(refusal(delivered, to: delivered.replacing(.delivered, with: at(80))) == nil)
        #expect(refusal(delivered, to: delivered.replacing(.pickedUp, with: at(70))) == nil)
    }

    @Test("A cancelled delivery's own prefix is ordered too")
    func aCancellationIsOrderedAgainstItsPrefix() {
        #expect(
            refusal(cancelledAtPickup, to: cancelledAtPickup.replacing(.cancelled, with: at(65)))
                == .outOfOrder(event: .cancelled, mustNotPrecede: .arrivedAtPickup)
        )
        #expect(refusal(cancelledAtPickup, to: cancelledAtPickup.replacing(.cancelled, with: at(72))) == nil)
    }

    // MARK: The shift's own bounds

    @Test("An event before the shift started is refused, naming the event")
    func anEventBeforeTheShiftIsRefused() {
        #expect(
            refusal(delivered, to: delivered.replacing(.accepted, with: shiftStart.addingTimeInterval(-60)))
                == .precedesShiftStart(.accepted)
        )
        #expect(
            refusal(delivered, to: delivered.replacing(.accepted, with: shiftStart)) == nil,
            "An acceptance exactly at the shift's start is inside it"
        )
    }

    @Test("An event after the shift ended is refused, naming the event")
    func anEventAfterTheShiftIsRefused() {
        #expect(
            refusal(delivered, to: delivered.replacing(.delivered, with: at(250)))
                == .followsShiftEnd(.delivered)
        )
        #expect(
            refusal(delivered, to: delivered.replacing(.delivered, with: at(240))) == nil,
            "A completion exactly at the shift's end is inside it"
        )
    }

    @Test("The shift's bounds are judged before the ordering inside them")
    func boundsAreJudgedBeforeOrdering() {
        // A proposal that is both outside the shift and out of order reports the
        // bound: a driver told their completion precedes its pickup would move
        // the pickup and meet the bound anyway.
        let proposed = delivered.replacing(.delivered, with: shiftStart.addingTimeInterval(-60))

        #expect(refusal(delivered, to: proposed) == .precedesShiftStart(.delivered))
    }

    @Test("A delivery on a shift that has not ended is refused before anything else")
    func aRunningShiftIsRefused() {
        // A shift with no recorded end has no window, and a delivery inside one
        // has no upper bound to be judged against. Reported before the proposal
        // itself is looked at.
        #expect(
            refusalOnRunningShift(delivered, to: delivered.replacing(.delivered, with: at(95)))
                == .shiftNotCompleted
        )
        #expect(
            refusalOnRunningShift(delivered, to: delivered.replacing(.delivered, with: at(75)))
                == .shiftNotCompleted,
            "and a proposal that is also out of order still reports the shift"
        )
    }

    private func refusalOnRunningShift(
        _ recorded: DeliveryLifecycleRecord,
        to proposed: DeliveryLifecycleRecord
    ) -> DeliveryTimeCorrectionRefusal? {
        do {
            _ = try DeliveryTimeCorrection(correcting: recorded, to: proposed, within: nil)
            return nil
        } catch let error as DeliveryTimeCorrectionRefusal {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }

    // MARK: Which stages exist

    @Test("A stage the delivery never recorded is not created")
    func anAbsentStageIsNotFabricated() {
        // A delivery cancelled at the counter never picked the order up. Writing
        // a pickup time here would put an event in a driver's history that never
        // happened.
        let withPickup = DeliveryLifecycleRecord(
            acceptedAt: at(60),
            arrivedAtPickupAt: at(70),
            pickedUpAt: at(80),
            cancelledAt: at(95)
        )

        #expect(refusal(cancelledAtPickup, to: withPickup) == .eventNotRecorded(.pickedUp))
    }

    @Test("`replacing` leaves an unrecorded stage unrecorded, so a draft cannot fabricate one")
    func replacingDoesNotCreateAStage() {
        let unchanged = cancelledAtPickup.replacing(.pickedUp, with: at(80))

        #expect(unchanged == cancelledAtPickup, "Nothing was written, and no stage came into existence")
    }

    @Test("A stage the delivery does record is not removed")
    func aRecordedStageIsNotRemoved() {
        let withoutArrival = DeliveryLifecycleRecord(acceptedAt: at(60), pickedUpAt: at(80), deliveredAt: at(120))

        #expect(refusal(delivered, to: withoutArrival) == .recordedEventRemoved(.arrivedAtPickup))
    }

    @Test("The terminal outcome cannot be swapped by a correction")
    func theTerminalOutcomeIsNotSwapped() {
        let asCancelled = DeliveryLifecycleRecord(
            acceptedAt: at(60),
            arrivedAtPickupAt: at(70),
            pickedUpAt: at(80),
            cancelledAt: at(120)
        )

        // Reported as the removal it is. Correcting a completion into a
        // cancellation is `HistoricalDeliveryCancellation`, which has its own
        // name and its own confirmation.
        #expect(refusal(delivered, to: asCancelled) == .recordedEventRemoved(.delivered))
    }

    @Test("A delivery that has not finished has no recorded history to correct")
    func anUnfinishedDeliveryIsRefused() {
        let active = DeliveryLifecycleRecord(acceptedAt: at(60), arrivedAtPickupAt: at(70))

        #expect(
            refusal(active, to: active.replacing(.arrivedAtPickup, with: at(75))) == .deliveryNotFinished
        )
    }

    @Test("A stored chain that already runs backwards is repairable rather than refused outright")
    func anAnomalousChainCanBeRepaired() throws {
        // A row the app cannot write: the completion is earlier than the pickup
        // it followed. Every other correction in the app refuses such a row,
        // because each has to *choose* which of two events was the mistake. This
        // one does not choose: the driver states both.
        let anomalous = DeliveryLifecycleRecord(
            acceptedAt: at(60),
            arrivedAtPickupAt: at(70),
            pickedUpAt: at(120),
            deliveredAt: at(90)
        )

        #expect(
            refusal(anomalous, to: anomalous)
                == .outOfOrder(event: .delivered, mustNotPrecede: .pickedUp),
            "Re-recording it unchanged is refused, because it is not a valid chain"
        )

        let repaired = try correction(anomalous, to: anomalous.replacing(.pickedUp, with: at(80)))
        #expect(repaired.corrected.pickedUpAt == at(80))
        #expect(repaired.corrected.deliveredAt == at(90), "and the completion was not moved for it")
    }

    // MARK: Wording

    @Test("Every refusal has a sentence, and none of them says only that something was wrong")
    func everyRefusalIsExplained() throws {
        for refusal in DeliveryTimeCorrectionRefusal.allCases {
            let sentence = try #require(
                DeliveryLifecycleError.invalidTimeCorrection(refusal).errorDescription,
                "\(refusal) has no sentence"
            )
            #expect(sentence.count > 40, "\(refusal) is described too briefly to be useful: \(sentence)")
            #expect(!sentence.lowercased().contains("invalid"), "\(refusal) says only that something was wrong")
            #expect(!sentence.contains("Edit"), "\(refusal) calls a correction an edit")
        }
    }

    @Test("The ordering refusal names both halves of the collision")
    func theOrderingRefusalNamesBothFacts() throws {
        let sentence = try #require(
            DeliveryLifecycleError
                .invalidTimeCorrection(.outOfOrder(event: .delivered, mustNotPrecede: .pickedUp))
                .errorDescription
        )

        #expect(sentence.contains("Delivered"))
        #expect(sentence.contains("picked up"))
        #expect(
            sentence.lowercased().contains("correct picked up as well"),
            "and it says the other one is corrected rather than moved for them. Showed: \(sentence)"
        )
    }

    @Test("The bound refusals name the event and say which boundary it crossed")
    func theBoundRefusalsNameTheEvent() throws {
        let early = try #require(
            DeliveryLifecycleError.invalidTimeCorrection(.precedesShiftStart(.accepted)).errorDescription
        )
        #expect(early.contains("Accepted"))
        #expect(early.contains("before this shift started"))

        let late = try #require(
            DeliveryLifecycleError.invalidTimeCorrection(.followsShiftEnd(.delivered)).errorDescription
        )
        #expect(late.contains("Delivered"))
        #expect(late.contains("after this shift ended"))
        #expect(
            late.contains("correct the shift's end time first"),
            "and it points at the editor that owns that fact. Showed: \(late)"
        )
    }

    @Test("Every refusal has a structural log name, and none of them is a description of its value")
    func everyRefusalLogsStructurally() {
        for refusal in DeliveryTimeCorrectionRefusal.allCases {
            let logged = refusal.logDescription
            #expect(!logged.isEmpty)
            #expect(
                !logged.contains("("),
                "\(refusal) logs its associated value, which is how an instant reaches a log"
            )
        }
    }

    @Test("The sheet's statements say what moves, what does not, and that nothing cascades")
    func theStatementsSayWhatChanges() {
        #expect(DeliveryTimeCorrectionStatement.derivedFiguresMove.contains("how long this delivery took"))
        #expect(DeliveryTimeCorrectionStatement.derivedFiguresMove.contains("waited at the pickup"))
        #expect(DeliveryTimeCorrectionStatement.derivedFiguresMove.contains("recorded delivery hour"))
        #expect(DeliveryTimeCorrectionStatement.derivedFiguresMove.contains("delivery active time"))

        #expect(DeliveryTimeCorrectionStatement.routeIsNotChanged.contains("not changed"))
        #expect(
            DeliveryTimeCorrectionStatement.routeIsNotChanged.contains("recorded mileage"),
            "The route promise has to name mileage, which is the figure a driver would fear moving"
        )

        #expect(DeliveryTimeCorrectionStatement.recordIsOtherwiseUnchanged.contains("pickup place"))
        #expect(DeliveryTimeCorrectionStatement.recordIsOtherwiseUnchanged.contains("offer"))
        #expect(DeliveryTimeCorrectionStatement.recordIsOtherwiseUnchanged.contains("tips"))

        #expect(
            DeliveryTimeCorrectionStatement.eachTimeIsCorrectedExplicitly.contains("never moves one of them"),
            "The no-cascade rule is stated before a driver meets it as a refusal"
        )
    }
}
