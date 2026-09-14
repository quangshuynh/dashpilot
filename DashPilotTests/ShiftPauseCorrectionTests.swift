import Foundation
import Testing
@testable import DashPilot

/// The rules a proposed pause correction is checked against, with no store and
/// no rendered view: the bounds, the positive-duration rule, the two overlap
/// rules and what each refusal says.
///
/// Every timestamp here is invented.
@Suite("Shift pause correction")
struct ShiftPauseCorrectionTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// An eight-hour shift, which every case below proposes a stretch inside.
    private var window: ClosedRange<Date> { start...at(8 * 3600) }

    private func correction(
        from startedAt: Date,
        to endedAt: Date,
        within shiftWindow: ClosedRange<Date>? = nil,
        pauses: [ShiftPauseInterval] = [],
        deliveries: [DeliveryActiveInterval] = []
    ) throws -> ShiftPauseCorrection {
        try ShiftPauseCorrection(
            startedAt: startedAt,
            endedAt: endedAt,
            within: shiftWindow ?? window,
            avoiding: pauses,
            and: deliveries
        )
    }

    // MARK: The three corrections

    @Test("A corrected start moves the start and leaves the end")
    func correctsTheStart() throws {
        let corrected = try correction(from: at(3_000), to: at(3_600))

        #expect(corrected.startedAt == at(3_000))
        #expect(corrected.endedAt == at(3_600))
        #expect(corrected.duration == 600)
    }

    @Test("A corrected end moves the end and leaves the start")
    func correctsTheEnd() throws {
        let corrected = try correction(from: at(3_600), to: at(5_400))

        #expect(corrected.startedAt == at(3_600))
        #expect(corrected.endedAt == at(5_400))
        #expect(corrected.duration == 1_800)
    }

    @Test("Both ends can move at once")
    func correctsBoth() throws {
        let corrected = try correction(from: at(1_200), to: at(2_400))

        #expect(corrected.startedAt == at(1_200))
        #expect(corrected.endedAt == at(2_400))
        #expect(corrected.duration == 1_200)
    }

    // MARK: Duration

    @Test("A pause ending before it started is refused")
    func refusesABackwardsPause() {
        #expect(throws: ShiftPauseCorrectionRefusal.notPositiveDuration) {
            try correction(from: at(3_600), to: at(3_000))
        }
    }

    @Test("A pause of no length is refused, because deleting one is a different action")
    func refusesAZeroLengthPause() {
        #expect(throws: ShiftPauseCorrectionRefusal.notPositiveDuration) {
            try correction(from: at(3_600), to: at(3_600))
        }
    }

    @Test("A pause of one second is accepted; the rule is positive, not long")
    func acceptsTheShortestPositivePause() throws {
        #expect(try correction(from: at(3_600), to: at(3_601)).duration == 1)
    }

    // MARK: The shift's own bounds

    @Test("A pause cannot begin before the shift did")
    func refusesAStartBeforeTheShift() {
        #expect(throws: ShiftPauseCorrectionRefusal.startsBeforeShift) {
            try correction(from: at(-1), to: at(600))
        }
    }

    @Test("A pause cannot end after the shift did")
    func refusesAnEndAfterTheShift() {
        #expect(throws: ShiftPauseCorrectionRefusal.endsAfterShift) {
            try correction(from: at(7 * 3600), to: at(8 * 3600 + 1))
        }
    }

    @Test("A pause filling the shift exactly is inside it")
    func acceptsThePauseFillingTheShift() throws {
        let corrected = try correction(from: start, to: at(8 * 3600))

        #expect(corrected.duration == 8 * 3600)
    }

    @Test("A shift that has not ended has no window, and every correction is refused")
    func refusesARunningShift() {
        #expect(throws: ShiftPauseCorrectionRefusal.shiftNotCompleted) {
            try ShiftPauseCorrection(
                startedAt: at(600),
                endedAt: at(1_200),
                within: nil,
                avoiding: [],
                and: []
            )
        }
    }

    @Test("The shift is checked before the timestamps, so a running shift is never told about them")
    func theRunningShiftRefusalOutranksTheRest() {
        #expect(throws: ShiftPauseCorrectionRefusal.shiftNotCompleted) {
            try ShiftPauseCorrection(
                startedAt: at(1_200),
                endedAt: at(600),
                within: nil,
                avoiding: [],
                and: []
            )
        }
    }

    // MARK: Overlapping another pause

    @Test("A stretch covering part of another recorded pause is refused")
    func refusesAnOverlappingPause() {
        let other = ShiftPauseInterval(start: at(3_600), end: at(5_400))

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsAnotherPause) {
            try correction(from: at(4_800), to: at(6_000), pauses: [other])
        }
    }

    @Test("A stretch swallowing another recorded pause whole is refused")
    func refusesASwallowingPause() {
        let other = ShiftPauseInterval(start: at(3_600), end: at(5_400))

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsAnotherPause) {
            try correction(from: at(3_000), to: at(6_000), pauses: [other])
        }
    }

    @Test("A stretch nested inside another recorded pause is refused")
    func refusesANestedPause() {
        let other = ShiftPauseInterval(start: at(3_600), end: at(5_400))

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsAnotherPause) {
            try correction(from: at(4_000), to: at(4_200), pauses: [other])
        }
    }

    @Test("Touching another pause is allowed: two adjacent breaks are not one claim twice")
    func allowsTouchingAnotherPause() throws {
        let other = ShiftPauseInterval(start: at(3_600), end: at(5_400))

        #expect(try correction(from: at(5_400), to: at(6_000), pauses: [other]).duration == 600)
        #expect(try correction(from: at(3_000), to: at(3_600), pauses: [other]).duration == 600)
    }

    @Test("An open pause among the others occupies the rest of the shift")
    func anOpenPauseOccupiesTheRestOfTheShift() {
        // A row a completed shift cannot hold through the app's own API, since
        // ending closes the open pause. A store holding one must not let a
        // correction be slipped underneath it, because the working-duration
        // calculation measures it to the shift's end.
        let open = ShiftPauseInterval(start: at(3_600), end: nil)

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsAnotherPause) {
            try correction(from: at(7 * 3600), to: at(7 * 3600 + 600), pauses: [open])
        }
    }

    @Test("A malformed stored pause blocks nothing, because it measures nothing")
    func aMalformedPauseBlocksNothing() throws {
        let malformed = ShiftPauseInterval(start: at(5_400), end: at(3_600))

        #expect(try correction(from: at(3_600), to: at(5_400), pauses: [malformed]).duration == 1_800)
    }

    @Test("A pause lying outside the shift blocks nothing inside it")
    func aPauseOutsideTheShiftBlocksNothing() throws {
        let outside = ShiftPauseInterval(start: at(9 * 3600), end: at(10 * 3600))

        #expect(try correction(from: at(3_600), to: at(5_400), pauses: [outside]).duration == 1_800)
    }

    // MARK: Overlapping delivery work

    @Test("A stretch overlapping a delivery's active interval is refused")
    func refusesOverlappingDeliveryWork() {
        let delivery = DeliveryActiveInterval(start: at(3_600), end: at(5_400))

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsDeliveryWork) {
            try correction(from: at(4_800), to: at(6_000), deliveries: [delivery])
        }
    }

    @Test("A pause that would swallow a whole delivery is refused")
    func refusesSwallowingADelivery() {
        let delivery = DeliveryActiveInterval(start: at(3_600), end: at(5_400))

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsDeliveryWork) {
            try correction(from: at(3_000), to: at(6_000), deliveries: [delivery])
        }
    }

    @Test("A pause beginning the instant a delivery finished is allowed")
    func allowsAPauseTouchingADelivery() throws {
        let delivery = DeliveryActiveInterval(start: at(3_600), end: at(5_400))

        #expect(try correction(from: at(5_400), to: at(6_000), deliveries: [delivery]).duration == 600)
        #expect(try correction(from: at(3_000), to: at(3_600), deliveries: [delivery]).duration == 600)
    }

    @Test("A pause between two deliveries is allowed")
    func allowsAPauseBetweenDeliveries() throws {
        let first = DeliveryActiveInterval(start: at(1_800), end: at(3_600))
        let second = DeliveryActiveInterval(start: at(7_200), end: at(9_000))

        #expect(
            try correction(from: at(4_200), to: at(6_600), deliveries: [first, second]).duration == 2_400
        )
    }

    @Test("A delivery with no recorded end blocks nothing, because it measures nothing")
    func anUnfinishedDeliveryBlocksNothing() throws {
        // A row a completed shift cannot hold either: a shift cannot end while a
        // delivery is active. An interval that cannot say when it ended is not
        // evidence that work happened at a particular moment, which is exactly
        // how `DeliveryActiveTimeCalculator` already treats it.
        let unfinished = DeliveryActiveInterval(start: at(3_600), end: nil)

        #expect(try correction(from: at(3_600), to: at(5_400), deliveries: [unfinished]).duration == 1_800)
    }

    @Test("A pause is refused for the other pause before it is refused for the delivery")
    func pauseOverlapOutranksDeliveryOverlap() {
        let other = ShiftPauseInterval(start: at(3_600), end: at(5_400))
        let delivery = DeliveryActiveInterval(start: at(3_600), end: at(5_400))

        #expect(throws: ShiftPauseCorrectionRefusal.overlapsAnotherPause) {
            try correction(from: at(4_000), to: at(4_800), pauses: [other], deliveries: [delivery])
        }
    }

    // MARK: What every refusal says

    @Test("Every refusal has a sentence that says what would make the stretch acceptable")
    func everyRefusalIsExplained() {
        for refusal in ShiftPauseCorrectionRefusal.allCases {
            let sentence = ShiftPauseCorrectionError.invalidCorrection(refusal).errorDescription
            let description = try? #require(sentence)
            #expect(description?.isEmpty == false, "\(refusal) has no sentence")
            #expect(
                description?.contains("invalid") == false,
                "\(refusal) says \"invalid\" rather than what is wrong"
            )
        }
    }

    @Test("A deletion prompt names the pause, its length and what grows because of it")
    func theDeletionPromptStatesTheConsequence() {
        let prompt = ShiftPauseDeletionPrompt.delete("Pause 2", duration: "30 min")

        #expect(prompt.title == "Delete Pause 2?")
        #expect(prompt.confirmTitle == "Delete Pause 2")
        #expect(prompt.detail.contains("30 min"))
        #expect(prompt.detail.contains("working time"))
        #expect(prompt.detail.contains("longer"), "The direction is stated, not left to be guessed")
        #expect(
            prompt.detail.contains("start and end times do not move"),
            "and so is what deleting a pause does not touch"
        )
        #expect(prompt.detail.contains("route recorded during it is not changed"))
        #expect(!prompt.detail.contains("Edit"))
    }
}
