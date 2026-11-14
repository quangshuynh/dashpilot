import Foundation
import Testing
@testable import DashPilot

/// The rules a corrected shift start and end are judged by, as plain values.
///
/// Every claim here is about **which instants are truthful**, independent of a
/// store: the clock, the shift's own end, the work it recorded, the shifts
/// around it, and what the corrected window measures. The service suite covers
/// what a correction writes.
///
/// Every timestamp here is invented.
@Suite("Shift time correction")
struct ShiftTimeCorrectionTests {
    private let utc: Calendar
    /// Wednesday, 17 June 2026, 09:00 UTC.
    private let nine: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        utc = calendar
        nine = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 9)))
    }

    /// `minutes` after 09:00.
    private func at(_ minutes: Double) -> Date { nine.addingTimeInterval(minutes * 60) }

    private var later: Date { at(24 * 60) }

    /// A finished 09:00 to 14:00 shift, corrected to the given times.
    private func correction(
        start: Date,
        end: Date? = nil,
        now: Date? = nil,
        pauses: [ShiftPauseInterval] = [],
        suspensions: [RouteSuspensionInterval] = [],
        events: [RecordedDeliveryEvent] = [],
        offers: [Date] = [],
        neighbours: ShiftTimeNeighbours = .none
    ) throws -> ShiftTimeCorrection {
        try ShiftTimeCorrection(
            start: start,
            end: end,
            recordedStart: nine,
            recordedEnd: at(300),
            now: now ?? later,
            pauses: pauses,
            suspensions: suspensions,
            deliveryEvents: events,
            offerAcceptances: offers,
            neighbours: neighbours
        )
    }

    /// A running shift that started at 09:00, read at `now`.
    private func runningCorrection(
        start: Date,
        end: Date? = nil,
        now: Date,
        pauses: [ShiftPauseInterval] = [],
        events: [RecordedDeliveryEvent] = [],
        neighbours: ShiftTimeNeighbours = .none
    ) throws -> ShiftTimeCorrection {
        try ShiftTimeCorrection(
            start: start,
            end: end,
            recordedStart: nine,
            recordedEnd: nil,
            now: now,
            pauses: pauses,
            suspensions: [],
            deliveryEvents: events,
            offerAcceptances: [],
            neighbours: neighbours
        )
    }

    private func refusal(_ body: () throws -> ShiftTimeCorrection) -> ShiftTimeCorrectionRefusal? {
        do {
            _ = try body()
            return nil
        } catch let refusal as ShiftTimeCorrectionRefusal {
            return refusal
        } catch {
            Issue.record("Unexpected error \(error)")
            return nil
        }
    }

    // MARK: Completed shifts

    @Test("A later start shortens a completed shift: 9:00 to 2:00 PM becomes 9:30 to 2:00 PM, 4 hours 30 minutes")
    func laterStartShortensTheShift() throws {
        let corrected = try correction(start: at(30))

        #expect(corrected.recordedElapsed(asOf: later) == 5 * 3600)
        #expect(corrected.correctedElapsed(asOf: later) == 4.5 * 3600)
        #expect(corrected.changesStart && !corrected.changesEnd)
        #expect(corrected.correctedEnd == at(300), "The end is kept exactly as recorded")
        #expect(corrected.routeTrimStartBoundary == at(30), "Route before the corrected start leaves the shift")
        #expect(corrected.routeTrimEndBoundary == nil)
    }

    @Test("An earlier start lengthens it and removes no route")
    func earlierStartRemovesNothing() throws {
        let corrected = try correction(start: at(-45))

        #expect(corrected.correctedElapsed(asOf: later) == 5.75 * 3600)
        #expect(corrected.routeTrimStartBoundary == nil, "Nothing lies before the recorded start to remove")
    }

    @Test("The end alone is judged by the end rules and leaves the start where it was")
    func endAloneKeepsTheStart() throws {
        let corrected = try correction(start: nine, end: at(270))

        #expect(!corrected.changesStart && corrected.changesEnd)
        #expect(corrected.correctedElapsed(asOf: later) == 4.5 * 3600)
        #expect(corrected.routeTrimEndBoundary == at(270))
    }

    @Test("Both times move together, judged as one window")
    func bothMoveTogether() throws {
        let corrected = try correction(start: at(30), end: at(330))

        #expect(corrected.changesStart && corrected.changesEnd)
        #expect(corrected.correctedElapsed(asOf: later) == 5 * 3600)
        #expect(corrected.routeTrimStartBoundary == at(30))
        #expect(corrected.routeTrimEndBoundary == nil, "A later end removes nothing")
    }

    @Test("Re-recording both times is accepted and changes nothing")
    func unchangedTimesAreAccepted() throws {
        let corrected = try correction(start: nine, end: at(300))

        #expect(!corrected.changesAnything)
        #expect(corrected.routeTrimStartBoundary == nil && corrected.routeTrimEndBoundary == nil)
    }

    // MARK: Validation

    @Test("A start at or after the recorded end is refused on the start")
    func startAfterEndIsRefused() {
        #expect(refusal { try correction(start: at(300)) } == .start(.notBeforeShiftEnd))
        #expect(refusal { try correction(start: at(301)) } == .start(.notBeforeShiftEnd))
    }

    @Test("An end earlier than a corrected start is refused on the end, the field being moved")
    func endBeforeCorrectedStartIsRefusedOnTheEnd() {
        #expect(refusal { try correction(start: at(120), end: at(60)) } == .end(.notAfterShiftStart))
        #expect(refusal { try correction(start: at(120), end: at(120)) } == .end(.notAfterShiftStart))
    }

    @Test("Neither time may be in the future")
    func futureTimesAreRefused() {
        let now = at(310)
        #expect(refusal { try correction(start: at(30), end: at(311), now: now) } == .end(.inFuture))
        #expect(refusal { try correction(start: at(30), end: at(310), now: now) } == nil, "Now itself is allowed")
        #expect(refusal { try runningCorrection(start: at(11), now: at(10)) } == .start(.inFuture))
    }

    @Test("A start after recorded delivery work is refused naming the earliest event")
    func startAfterDeliveryWorkNamesTheEarliestEvent() {
        let accepted = RecordedDeliveryEvent(deliveryNumber: 2, event: .accepted, occurredAt: at(20))
        let delivered = RecordedDeliveryEvent(deliveryNumber: 1, event: .delivered, occurredAt: at(90))

        #expect(
            refusal { try correction(start: at(25), events: [delivered, accepted]) }
                == .start(.followsRecordedDeliveryWork(accepted))
        )
        #expect(refusal { try correction(start: at(20), events: [delivered, accepted]) } == nil,
                "A start at the very instant of the first acceptance keeps the work inside the shift")
    }

    @Test("A start after a recorded pause, parked stretch or offer acceptance is refused")
    func startAfterRecordedStretchesIsRefused() {
        let pause = ShiftPauseInterval(start: at(40), end: at(60))
        #expect(refusal { try correction(start: at(45), pauses: [pause]) } == .start(.followsRecordedPause))
        #expect(refusal { try correction(start: at(40), pauses: [pause]) } == nil)

        let parked = RouteSuspensionInterval(start: at(50), end: at(55))
        #expect(refusal { try correction(start: at(51), suspensions: [parked]) } == .start(.followsRecordedRouteSuspension))

        #expect(refusal { try correction(start: at(31), offers: [at(30)]) } == .start(.followsRecordedOfferAcceptance))
    }

    @Test("A start inside the previous shift is refused; one at its very end is not")
    func previousShiftBoundsTheStart() {
        let previous = ShiftTimeNeighbours(
            previous: RecordedShiftSpan(startedAt: at(-300), endedAt: at(-30)),
            nextStartedAt: nil,
            nextAfterRecordedStartStartedAt: nil
        )
        #expect(refusal { try correction(start: at(-31), neighbours: previous) } == .start(.overlapsAnotherShift))
        #expect(refusal { try correction(start: at(-30), neighbours: previous) } == nil)

        let stillRunning = ShiftTimeNeighbours(
            previous: RecordedShiftSpan(startedAt: at(-300), endedAt: nil),
            nextStartedAt: nil,
            nextAfterRecordedStartStartedAt: nil
        )
        #expect(refusal { try correction(start: at(-10), neighbours: stillRunning) } == .start(.overlapsAnotherShift))
    }

    @Test("Moving the start earlier past a whole shift is refused")
    func jumpingOverAShiftIsRefused() {
        // The other shift ran 06:00 to 07:00; this one starts at 09:00.
        let between = ShiftTimeNeighbours(previous: nil, nextStartedAt: at(-180), nextAfterRecordedStartStartedAt: nil)
        #expect(refusal { try correction(start: at(-240), neighbours: between) } == .start(.overlapsAnotherShift))
    }

    @Test("An end reaching into the next shift is still refused on the end")
    func nextShiftBoundsTheEnd() {
        let next = ShiftTimeNeighbours(previous: nil, nextStartedAt: at(360), nextAfterRecordedStartStartedAt: at(360))
        #expect(refusal { try correction(start: nine, end: at(361), neighbours: next) } == .end(.overlapsAnotherShift))
        #expect(refusal { try correction(start: nine, end: at(360), neighbours: next) } == nil)
    }

    @Test("An unmoved start is not judged again, so an end-only correction is refused only for the end rules")
    func unmovedStartIsNotRejudged() {
        // A store the app cannot write: a pause beginning before the shift.
        let anomalous = ShiftPauseInterval(start: at(-10), end: at(5))
        #expect(refusal { try correction(start: nine, end: at(280), pauses: [anomalous]) } == nil)
        #expect(refusal { try correction(start: at(1), pauses: [anomalous]) } == .start(.followsRecordedPause))
    }

    // MARK: Running shifts

    @Test("A running shift's start is corrected without giving it an end")
    func runningShiftStartIsCorrected() throws {
        let corrected = try runningCorrection(start: at(-20), now: at(120))

        #expect(corrected.isRunningShift)
        #expect(corrected.correctedEnd == nil, "Still running")
        #expect(corrected.recordedElapsed(asOf: at(120)) == 2 * 3600)
        #expect(corrected.correctedElapsed(asOf: at(120)) == 140 * 60)
        #expect(corrected.correctedElapsed(asOf: at(180)) == 200 * 60, "The timer continues from the corrected start")
    }

    @Test("A running shift cannot be handed an end through a time correction")
    func runningShiftCannotBeEnded() {
        #expect(refusal { try runningCorrection(start: nine, end: at(60), now: at(120)) } == .end(.shiftNotCompleted))
    }

    @Test("A running shift's start must still precede its first recorded work")
    func runningShiftStartRespectsWork() {
        let accepted = RecordedDeliveryEvent(deliveryNumber: 1, event: .accepted, occurredAt: at(15))
        #expect(
            refusal { try runningCorrection(start: at(16), now: at(60), events: [accepted]) }
                == .start(.followsRecordedDeliveryWork(accepted))
        )
    }

    @Test("Working time over a corrected window excludes only the paused time inside it")
    func workingTimeFollowsTheCorrectedWindow() throws {
        let pauses = [ShiftPauseInterval(start: at(60), end: at(90))]
        let corrected = try correction(start: at(30), pauses: pauses)

        #expect(corrected.correctedWorking(pauses: pauses, asOf: later) == 4 * 3600)

        // A running shift with an open pause: working time stops growing.
        let open = [ShiftPauseInterval(start: at(100), end: nil)]
        let running = try runningCorrection(start: at(-20), now: at(160), pauses: open)
        #expect(running.correctedWorking(pauses: open, asOf: at(160)) == 120 * 60)
        #expect(running.correctedWorking(pauses: open, asOf: at(200)) == 120 * 60)
    }

    // MARK: Midnight, weeks and months

    @Test("A shift crossing midnight keeps its day when the start stays before midnight")
    func crossMidnightShift() throws {
        // 23:30 to 02:00 the next morning.
        let corrected = try ShiftTimeCorrection(
            start: at(14 * 60), end: nil, recordedStart: at(14 * 60 + 30), recordedEnd: at(17 * 60),
            now: later.addingTimeInterval(86_400), pauses: [], suspensions: [], deliveryEvents: [],
            offerAcceptances: [], neighbours: .none
        )
        #expect(corrected.correctedElapsed(asOf: later) == 3 * 3600)
        #expect(corrected.reportingMove(calendar: utc) == nil, "Both starts are on Wednesday")
    }

    @Test("A start corrected across Monday midnight moves the shift into the previous week")
    func weekBoundaryMove() throws {
        // Monday 22 June 2026, 00:10 corrected to Sunday 21 June, 23:50.
        let monday = try #require(utc.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 0, minute: 10)))
        let sunday = monday.addingTimeInterval(-20 * 60)
        let corrected = try ShiftTimeCorrection(
            start: sunday, end: nil, recordedStart: monday, recordedEnd: monday.addingTimeInterval(4 * 3600),
            now: monday.addingTimeInterval(86_400), pauses: [], suspensions: [], deliveryEvents: [],
            offerAcceptances: [], neighbours: .none
        )
        let move = try #require(corrected.reportingMove(calendar: utc))

        #expect(move.changesWeek)
        #expect(!move.changesMonth)
        #expect(move.fromWeek.contains(monday) && move.toWeek.contains(sunday))
        #expect(move.toWeek.end == move.fromWeek.start, "Adjacent weeks")
        #expect(
            move.statement(calendar: utc, locale: Locale(identifier: "en_US"))
                == "This shift will count on Sunday, Jun 21 instead of Monday, Jun 22, in the week of Jun 15. Both periods' totals update."
        )
    }

    @Test("A start corrected across the first of the month names the month it moves into")
    func monthBoundaryMove() throws {
        // Wednesday 1 July 00:05 corrected to Tuesday 30 June 23:40: same week.
        let first = try #require(utc.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 0, minute: 5)))
        let move = try #require(ShiftReportingMove(from: first, to: first.addingTimeInterval(-25 * 60), calendar: utc))

        #expect(move.changesMonth)
        #expect(!move.changesWeek)
        #expect(
            move.statement(calendar: utc, locale: Locale(identifier: "en_US"))
                == "This shift will count on Tuesday, Jun 30 instead of Wednesday, Jul 1, in June 2026. Both periods' totals update."
        )
    }

    // MARK: Daylight saving

    @Test("Durations across the autumn change are the hours that passed, not the clock difference")
    func fallBackDuration() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // Sunday 1 November 2026: 02:00 EDT becomes 01:00 EST.
        let start = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30)))
        let end = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 3)))
        #expect(end.timeIntervalSince(start) == 3.5 * 3600, "The fixture spans the repeated hour")

        // 01:30 EST, the second 01:30 of the night.
        let secondOneThirty = start.addingTimeInterval(2 * 3600)
        let corrected = try ShiftTimeCorrection(
            start: secondOneThirty, end: nil, recordedStart: start, recordedEnd: end,
            now: end.addingTimeInterval(86_400), pauses: [], suspensions: [], deliveryEvents: [],
            offerAcceptances: [], neighbours: .none
        )
        #expect(corrected.correctedElapsed(asOf: end) == 1.5 * 3600)
        #expect(corrected.reportingMove(calendar: newYork) == nil, "Still Sunday")
    }

    @Test("Durations across the spring change lose the skipped hour")
    func springForwardDuration() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // Sunday 8 March 2026: 02:00 EST becomes 03:00 EDT.
        let start = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)))
        let end = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 4)))
        let earlier = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1)))

        let corrected = try ShiftTimeCorrection(
            start: earlier, end: nil, recordedStart: start, recordedEnd: end,
            now: end.addingTimeInterval(86_400), pauses: [], suspensions: [], deliveryEvents: [],
            offerAcceptances: [], neighbours: .none
        )
        #expect(corrected.recordedElapsed(asOf: end) == 1.5 * 3600, "01:30 EST to 04:00 EDT is 90 minutes")
        #expect(corrected.correctedElapsed(asOf: end) == 2 * 3600)
    }

    // MARK: Wording

    @Test("Every start refusal has a sentence, and none logs an instant")
    func everyStartRefusalHasASentence() {
        for refusal in ShiftStartCorrectionRefusal.allCases {
            let sentence = ShiftTimeCorrectionError.invalidCorrection(.start(refusal)).errorDescription ?? ""
            #expect(!sentence.isEmpty, "\(refusal.logDescription)")
            #expect(!refusal.logDescription.contains(":"), "A structural name, not a time")
        }
        for refusal in ShiftEndCorrectionRefusal.allCases {
            #expect(!(ShiftTimeCorrectionError.invalidCorrection(.end(refusal)).errorDescription ?? "").isEmpty)
        }
    }

    @Test("The route prompt appears only when positions would be deleted, and counts each side")
    func routePromptCountsEachSide() throws {
        #expect(
            ShiftTimeCorrectionPrompt.trimmingRoute(beforeStart: 0, afterEnd: 0, correctedStart: "9:30 AM", correctedEnd: nil)
                == nil
        )
        let prompt = try #require(
            ShiftTimeCorrectionPrompt.trimmingRoute(
                beforeStart: 1, afterEnd: 12, correctedStart: "9:30 AM", correctedEnd: "1:40 PM"
            )
        )
        #expect(prompt.detail.hasPrefix("This shift recorded 1 recorded position before 9:30 AM and 12 recorded positions after 1:40 PM."))
        #expect(prompt.detail.contains("cannot be undone"))
        #expect(prompt.confirmTitle == "Correct Times and Remove")
    }
}
