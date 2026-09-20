import Foundation
import Testing
@testable import DashPilot

/// The rule that decides which end times a finished shift may be corrected to,
/// tested as the plain value it is: no store, no container, no rendered view.
///
/// ## What is being asserted here
///
/// Two kinds of claim. First, that every refusal is a refusal: nothing is
/// clamped, swapped, trimmed or nudged into an acceptable instant, so a
/// correction that collides with a recorded fact throws rather than quietly
/// rewriting the fact. Second, that the one thing this value decides about the
/// route is a **boundary**, never a distance: it says which positions are still
/// inside the shift and nothing at all about how far they are apart.
///
/// Every timestamp here is invented.
@Suite("Shift end correction")
struct ShiftEndCorrectionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    /// A correction on a four-hour shift with nothing else recorded.
    private func correction(
        to correctedEnd: Date,
        pauses: [ShiftPauseInterval] = [],
        deliveryEvents: [Date] = [],
        nextShiftStartedAt: Date? = nil
    ) throws -> ShiftEndCorrection {
        try ShiftEndCorrection(
            to: correctedEnd,
            startedAt: start,
            recordedEnd: at(240),
            pauses: pauses,
            deliveryEvents: deliveryEvents,
            nextShiftStartedAt: nextShiftStartedAt
        )
    }

    private func refusal(
        to correctedEnd: Date,
        pauses: [ShiftPauseInterval] = [],
        deliveryEvents: [Date] = [],
        nextShiftStartedAt: Date? = nil
    ) -> ShiftEndCorrectionRefusal? {
        refusal {
            try correction(
                to: correctedEnd,
                pauses: pauses,
                deliveryEvents: deliveryEvents,
                nextShiftStartedAt: nextShiftStartedAt
            )
        }
    }

    /// The same proposal against a shift that has **not** ended.
    ///
    /// Its own helper rather than a `recordedEnd` parameter defaulting to the
    /// four-hour end: an optional whose default is "use the fixture's" cannot
    /// also express "there is no end", which is the whole of what this case is.
    private func runningShiftRefusal(
        to correctedEnd: Date,
        deliveryEvents: [Date] = []
    ) -> ShiftEndCorrectionRefusal? {
        refusal {
            try ShiftEndCorrection(
                to: correctedEnd,
                startedAt: start,
                recordedEnd: nil,
                pauses: [],
                deliveryEvents: deliveryEvents,
                nextShiftStartedAt: nil
            )
        }
    }

    private func refusal(_ build: () throws -> ShiftEndCorrection) -> ShiftEndCorrectionRefusal? {
        do {
            _ = try build()
            return nil
        } catch let error as ShiftEndCorrectionRefusal {
            return error
        } catch {
            return nil
        }
    }

    // MARK: What a correction carries

    @Test("An earlier end reports the direction it moved and the boundary route is judged against")
    func earlierEndCarriesATrimBoundary() throws {
        let corrected = try correction(to: at(220))

        #expect(corrected.recordedEnd == at(240))
        #expect(corrected.correctedEnd == at(220))
        #expect(corrected.movesEarlier)
        #expect(!corrected.movesLater)
        #expect(corrected.movement == 20 * 60)
        #expect(
            corrected.routeTrimBoundary == at(220),
            "Route is judged against the corrected end itself, not against some margin around it"
        )
    }

    @Test("A later end takes nothing out of the shift, so there is no boundary to trim to")
    func laterEndTrimsNothing() throws {
        let corrected = try correction(to: at(260))

        #expect(corrected.movesLater)
        #expect(!corrected.movesEarlier)
        #expect(corrected.movement == 20 * 60)
        #expect(
            corrected.routeTrimBoundary == nil,
            "Capture is judged against the end as positions arrive, so a longer shift has nothing beyond it"
        )
    }

    @Test("Re-recording the end a shift already has is accepted and moves nothing")
    func unchangedEndIsAccepted() throws {
        let corrected = try correction(to: at(240))

        #expect(!corrected.movesEarlier)
        #expect(!corrected.movesLater)
        #expect(corrected.movement == 0)
        #expect(corrected.routeTrimBoundary == nil)
    }

    // MARK: The shift itself

    @Test("A shift that has not ended has no end to correct")
    func runningShiftIsRefused() {
        #expect(runningShiftRefusal(to: at(220)) == .shiftNotCompleted)
    }

    @Test("An end at or before the start is refused, zero length included")
    func endMustFollowTheStart() {
        #expect(refusal(to: start.addingTimeInterval(-1)) == .notAfterShiftStart)
        #expect(refusal(to: start) == .notAfterShiftStart, "A shift of no length is not a correction anybody means")
        #expect(refusal(to: start.addingTimeInterval(1)) == nil)
    }

    @Test("An end after the start is accepted however far it moves, in either direction")
    func theEndIsNotOtherwiseBounded() {
        #expect(refusal(to: at(1)) == nil, "A shift can truthfully have been a minute long")
        #expect(refusal(to: at(10_000)) == nil, "and nothing here decides a shift was too long")
    }

    // MARK: Pauses

    @Test("An end before a recorded pause ends is refused rather than trimming the pause")
    func pauseReachingPastTheEndIsRefused() {
        let pause = ShiftPauseInterval(start: at(100), end: at(130))

        #expect(refusal(to: at(120), pauses: [pause]) == .cutsThroughRecordedPause)
        #expect(
            refusal(to: at(90), pauses: [pause]) == .cutsThroughRecordedPause,
            "and a pause left wholly outside the shift is the same refusal"
        )
    }

    @Test("An end exactly where a pause ended is accepted")
    func touchingAPauseIsNotCuttingThroughOne() {
        let pause = ShiftPauseInterval(start: at(100), end: at(130))

        #expect(
            refusal(to: at(130), pauses: [pause]) == nil,
            "A pause that ends as the shift does is inside it, exactly as ending a paused shift records"
        )
    }

    @Test("A pause the driver never ended is refused outright, in either direction")
    func openPauseIsRefused() {
        let open = ShiftPauseInterval(start: at(100), end: nil)

        #expect(refusal(to: at(220), pauses: [open]) == .pauseIsOpen)
        #expect(
            refusal(to: at(260), pauses: [open]) == .pauseIsOpen,
            "A later end would silently lengthen a stretch the driver never touched"
        )
    }

    @Test("A malformed pause is judged by the later of its two timestamps")
    func malformedPauseIsJudgedByItsLatestInstant() {
        // A row the app cannot write: the end precedes the start. The instant a
        // corrected window would have to reach to still contain it is the start.
        let backwards = ShiftPauseInterval(start: at(130), end: at(100))

        #expect(refusal(to: at(120), pauses: [backwards]) == .cutsThroughRecordedPause)
        #expect(refusal(to: at(130), pauses: [backwards]) == nil)
    }

    @Test("Only the pause that reaches furthest decides")
    func thePausesAreJudgedTogether() {
        let pauses = [
            ShiftPauseInterval(start: at(30), end: at(60)),
            ShiftPauseInterval(start: at(100), end: at(130))
        ]

        #expect(refusal(to: at(140), pauses: pauses) == nil)
        #expect(refusal(to: at(120), pauses: pauses) == .cutsThroughRecordedPause)
    }

    // MARK: Delivery work

    @Test("An end before anything a delivery recorded is refused")
    func endBeforeRecordedDeliveryWorkIsRefused() {
        let events = [at(100), at(105), at(110), at(150)]

        #expect(refusal(to: at(140), deliveryEvents: events) == .precedesRecordedDeliveryWork)
        #expect(refusal(to: at(150), deliveryEvents: events) == nil, "An end exactly at the last event is inside it")
        #expect(refusal(to: at(160), deliveryEvents: events) == nil)
    }

    @Test("Every recorded instant counts, not only the one the lifecycle reached last")
    func anOutOfOrderChainIsStillJudgedByItsLatestInstant() {
        // A store the app cannot write: a completion earlier than the pickup it
        // follows. An end moved back past the pickup would still be putting
        // recorded work outside its shift.
        let events = [at(100), at(180), at(150)]

        #expect(refusal(to: at(170), deliveryEvents: events) == .precedesRecordedDeliveryWork)
    }

    @Test("A shift with no deliveries is bounded by nothing but its own start")
    func noDeliveriesBoundNothing() {
        #expect(refusal(to: at(1), deliveryEvents: []) == nil)
    }

    // MARK: Another shift

    @Test("An end reaching into the next shift is refused")
    func overlappingTheNextShiftIsRefused() {
        #expect(refusal(to: at(300), nextShiftStartedAt: at(280)) == .overlapsAnotherShift)
        #expect(
            refusal(to: at(280), nextShiftStartedAt: at(280)) == nil,
            "A shift ending exactly as the next one begins is two shifts, not an overlap"
        )
        #expect(refusal(to: at(270), nextShiftStartedAt: at(280)) == nil)
    }

    @Test("The next shift bounds only the end, never the start")
    func theNextShiftDoesNotRefuseAnEarlierEnd() {
        #expect(refusal(to: at(120), nextShiftStartedAt: at(280)) == nil)
    }

    // MARK: Which refusal wins

    @Test("The shift's own two facts are judged before anything recorded inside it")
    func refusalOrderIsStable() {
        // A running shift with a delivery reaching past the proposed end reports
        // that it is running: there is no end to correct, so nothing else about
        // the proposal is worth saying.
        #expect(runningShiftRefusal(to: at(120), deliveryEvents: [at(200)]) == .shiftNotCompleted)
        #expect(
            refusal(to: start, deliveryEvents: [at(200)]) == .notAfterShiftStart,
            "and an end before the start is refused before what lies after it is considered"
        )
    }

    // MARK: Wording

    @Test("Every refusal has a sentence, and none of them says only that something was wrong")
    func everyRefusalIsExplained() throws {
        for refusal in ShiftEndCorrectionRefusal.allCases {
            let sentence = try #require(
                ShiftEndCorrectionError.invalidCorrection(refusal).errorDescription,
                "\(refusal) has no sentence"
            )
            #expect(sentence.count > 40, "\(refusal) is described too briefly to be useful: \(sentence)")
            #expect(!sentence.lowercased().contains("invalid"), "\(refusal) says only that something was wrong")
            #expect(!sentence.contains("Edit"), "\(refusal) calls a correction an edit")
        }
    }

    @Test("The trimming confirmation counts the positions, names the time and refuses the proportional reading")
    func trimmingPromptSaysWhatIsDestroyed() {
        let prompt = ShiftEndCorrectionPrompt.trimmingRoute(positionCount: 10, correctedEnd: "9:20 PM")

        #expect(prompt.title.contains("9:20 PM"))
        #expect(prompt.detail.contains("10 recorded positions"))
        #expect(prompt.detail.contains("deleted"))
        #expect(
            prompt.detail.contains("measured again"),
            "The sentence has to say the mileage is re-measured rather than reduced"
        )
        #expect(prompt.detail.contains("not reduced by the same share as the time"))
        #expect(prompt.detail.contains("cannot be undone"))
        #expect(prompt.confirmTitle != "OK", "The confirming button says what it does")
    }

    @Test("One position is counted in the singular")
    func trimmingPromptCountsOneCorrectly() {
        let prompt = ShiftEndCorrectionPrompt.trimmingRoute(positionCount: 1, correctedEnd: "9:20 PM")

        #expect(prompt.detail.contains("1 recorded position after"))
        #expect(!prompt.detail.contains("1 recorded positions"))
    }
}
