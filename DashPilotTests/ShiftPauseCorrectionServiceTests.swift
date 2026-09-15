import Foundation
import SwiftData
import Testing
@testable import DashPilot

private struct RefusedPauseSave: Error {}

/// Correcting a recorded pause through the store: what one correction writes,
/// which corrections are refused, what must not move because of one, and what a
/// refused save leaves behind.
///
/// ## Why so much of this suite is about things not moving
///
/// A pause is subtracted from a shift's elapsed time to produce the working
/// duration every hourly figure in the app divides by, so a corrected pause is
/// meant to move exactly four things: the shift's paused time, its working
/// duration, the rate over that working duration, and the period aggregates that
/// sum working durations. Everything else a finished shift reports is derived
/// from facts a pause does not touch, and the interesting claims are that they
/// stay exactly where they were: its elapsed duration, its delivery active time,
/// its recorded mileage, its route segments and gaps, and its gross earnings.
///
/// Rollback is read through a **fresh context** wherever the claim is about the
/// store, because an already-held model and the authoritative store can disagree
/// after a rollback, and the store is what a relaunch would show.
///
/// Every timestamp, amount and coordinate here is invented.
@MainActor
@Suite("Shift pause correction service")
struct ShiftPauseCorrectionServiceTests {
    private let calendar: Calendar
    private let start: Date
    private let day: ReportingPeriod

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        self.calendar = calendar

        // Wednesday, 17 June 2026, midnight UTC.
        start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17)))
        day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotPauseCorrectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    private func corrections(_ context: ModelContext) -> ShiftPauseCorrectionService {
        ShiftPauseCorrectionService(context: context)
    }

    private func refusing(_ context: ModelContext) -> ShiftPauseCorrectionService {
        ShiftPauseCorrectionService(context: context, commit: { _ in throw RefusedPauseSave() })
    }

    /// A four-hour shift paused once from 01:00 to 01:30, recorded entirely
    /// through the shipping services so the store holds what the app produces.
    @discardableResult
    private func pausedShift(in context: ModelContext) throws -> Shift {
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        try shifts.endActiveShift(at: at(4 * 3600))
        return shift
    }

    private func onlyPause(of shift: Shift) throws -> ShiftPause {
        try #require(shift.pausesInOrder.first)
    }

    /// A number of seconds, typed as the duration it is.
    ///
    /// `#expect(aTimeInterval? == seconds(4 * 3600 - 1_800))` type-checks and is always
    /// false: the arithmetic settles on `Int`, and the only `==` that accepts an
    /// optional `Double` on one side and an `Int` on the other is the
    /// `AnyHashable` overload, which compares the *types* first. Wrapping the
    /// expression makes the literals doubles and the comparison numeric.
    private func seconds(_ value: TimeInterval) -> TimeInterval { value }

    // MARK: Correcting the start

    @Test("A corrected start moves the start, leaves the end, and lengthens the working duration")
    func correctsTheStart() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)

        #expect(shift.completedWorkingDuration == seconds(4 * 3600 - 1_800))

        // The driver paused ten minutes before they meant to.
        try corrections(context).correct(pause, from: at(4_200), to: at(5_400))

        #expect(pause.startedAt == at(4_200))
        #expect(pause.endedAt == at(5_400), "The end the driver did not touch stays exactly as recorded")
        #expect(shift.completedPausedTime?.duration == 1_200)
        #expect(shift.completedWorkingDuration == seconds(4 * 3600 - 1_200))
        #expect(!context.hasChanges, "The correction was saved, not left pending")
    }

    @Test("A corrected end moves the end and leaves the start")
    func correctsTheEnd() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)

        // The driver forgot to resume for a quarter of an hour.
        try corrections(context).correct(pause, from: at(3_600), to: at(4_500))

        #expect(pause.startedAt == at(3_600))
        #expect(pause.endedAt == at(4_500))
        #expect(shift.completedPausedTime?.duration == 900)
        #expect(shift.completedWorkingDuration == seconds(4 * 3600 - 900))
    }

    @Test("Both ends move together, in one save")
    func correctsBothEnds() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)

        try corrections(context).correct(pause, from: at(7_200), to: at(10_800))

        #expect(pause.startedAt == at(7_200))
        #expect(pause.endedAt == at(10_800))
        #expect(shift.completedPausedTime?.duration == 3_600)
        #expect(shift.completedPausedTime?.intervalCount == 1, "One row, corrected. Not a second one")
        #expect(!context.hasChanges)
    }

    @Test("A correction survives a reopen of the store")
    func theCorrectionIsPersisted() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try pausedShift(in: context)
        let shiftID = shift.id
        try corrections(context).correct(try onlyPause(of: shift), from: at(4_200), to: at(4_800))

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.pauses.count == 1)
        #expect(stored.pausesInOrder.first?.startedAt == at(4_200))
        #expect(stored.pausesInOrder.first?.endedAt == at(4_800))
        #expect(stored.completedWorkingDuration == seconds(4 * 3600 - 600))
    }

    // MARK: Deleting

    @Test("A deleted pause is gone, and the shift's working time grows by its length")
    func deletesAPause() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)

        try corrections(context).delete(try onlyPause(of: shift))

        #expect(shift.pauses.isEmpty)
        #expect(shift.completedPausedTime?.hasPauses == false)
        #expect(shift.completedPausedTime?.intervalCount == 0)
        #expect(
            shift.completedWorkingDuration == shift.completedDuration,
            "With no pause left to subtract, working time is the elapsed time to the second"
        )
        #expect(!context.hasChanges)
    }

    @Test("Deleting one of two pauses leaves the other exactly as it was")
    func deletesOnlyTheChosenPause() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        try shifts.pauseActiveShift(at: at(9_000))
        try shifts.resumeActiveShift(at: at(10_800))
        try shifts.endActiveShift(at: at(4 * 3600))

        try corrections(context).delete(try #require(shift.pausesInOrder.first))

        #expect(shift.pauses.count == 1)
        let remaining = try #require(shift.pausesInOrder.first)
        #expect(remaining.startedAt == at(9_000))
        #expect(remaining.endedAt == at(10_800))
        #expect(shift.completedPausedTime?.duration == 1_800)
    }

    @Test("Deleting a pause leaves the shift's own start and end where they were")
    func deletingKeepsTheShiftsOwnTimestamps() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)

        try corrections(context).delete(try onlyPause(of: shift))

        #expect(shift.startedAt == start)
        #expect(shift.endedAt == at(4 * 3600))
        #expect(shift.completedDuration == seconds(4 * 3600))
    }

    @Test("A deleted pause is gone from the store, not only from the object")
    func theDeletionIsPersisted() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try pausedShift(in: context)
        let shiftID = shift.id
        try corrections(context).delete(try onlyPause(of: shift))

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.pauses.isEmpty)
        #expect(try reopened.fetch(FetchDescriptor<ShiftPause>()).isEmpty, "No orphaned row is left behind")
        #expect(stored.completedWorkingDuration == seconds(4 * 3600))
    }

    // MARK: Adding a pause that was not recorded

    @Test("A missed pause is recorded with the driver's own two timestamps")
    func addsAMissedPause() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(4 * 3600))

        let added = try corrections(context).addMissedPause(on: shift, from: at(7_200), to: at(9_000))

        #expect(added.startedAt == at(7_200))
        #expect(added.endedAt == at(9_000))
        #expect(added.isOpen == false, "An added pause is a completed one. It never opens a live pause")
        #expect(shift.pauses.count == 1)
        #expect(shift.completedPausedTime?.duration == 1_800)
        #expect(shift.completedWorkingDuration == seconds(4 * 3600 - 1_800))
        #expect(!context.hasChanges)
    }

    @Test("Adding a pause does not make the shift paused, and leaves its own timestamps alone")
    func addingAPauseChangesNoLifecycleState() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(4 * 3600))

        try corrections(context).addMissedPause(on: shift, from: at(7_200), to: at(9_000))

        #expect(shift.lifecycleState == .ended)
        #expect(shift.isPaused == false)
        #expect(shift.openPause == nil)
        #expect(shift.startedAt == start)
        #expect(shift.endedAt == at(4 * 3600))
        // The shift is still finished, so nothing else in the app thinks a shift
        // is running: this is the fetch relaunch recovery uses.
        #expect(try ShiftService(context: context).activeShift() == nil)
    }

    @Test("A second missed pause can be added beside the first")
    func addsASecondMissedPause() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(4 * 3600))
        let service = corrections(context)

        try service.addMissedPause(on: shift, from: at(3_600), to: at(5_400))
        try service.addMissedPause(on: shift, from: at(7_200), to: at(9_000))

        #expect(shift.pauses.count == 2)
        #expect(shift.completedPausedTime?.duration == 3_600)
        #expect(shift.numberedPauses.map(\.title) == ["Pause 1", "Pause 2"])
    }

    @Test("An added pause survives a reopen of the store")
    func theAdditionIsPersisted() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(4 * 3600))
        let shiftID = shift.id
        try corrections(context).addMissedPause(on: shift, from: at(7_200), to: at(9_000))

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.pauses.count == 1)
        #expect(stored.pausesInOrder.first?.startedAt == at(7_200))
        #expect(stored.completedWorkingDuration == seconds(4 * 3600 - 1_800))
    }

    // MARK: Refusals

    @Test("A running shift's pause cannot be corrected, deleted or added to")
    func refusesARunningShift() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        let pause = try onlyPause(of: shift)
        let service = corrections(context)

        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.shiftNotCompleted)) {
            try service.correct(pause, from: at(4_200), to: at(4_800))
        }
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.shiftNotCompleted)) {
            try service.delete(pause)
        }
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.shiftNotCompleted)) {
            try service.addMissedPause(on: shift, from: at(7_200), to: at(9_000))
        }

        #expect(pause.startedAt == at(3_600), "A refusal is not a correction")
        #expect(pause.endedAt == at(5_400))
        #expect(shift.pauses.count == 1)
        #expect(!context.hasChanges)
    }

    @Test("The open pause of a paused shift belongs to Resume and End alone")
    func refusesTheOpenPause() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        let open = try #require(shift.openPause)
        let service = corrections(context)

        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.shiftNotCompleted)) {
            try service.correct(open, from: at(4_200), to: at(4_800))
        }
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.pauseIsOpen)) {
            try service.delete(open)
        }

        #expect(shift.isPaused, "The shift is exactly as paused as it was")
        #expect(shift.openPause?.startedAt == at(3_600))
        #expect(!context.hasChanges)
    }

    @Test("The model refuses an open pause even where a shift somehow holds one after ending")
    func theModelRefusesAnOpenPauseDirectly() throws {
        // A row the app cannot write, since ending a shift closes its open
        // pause. The guard is on the model rather than only in the service, so
        // no future caller can reach around it.
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let open = ShiftPause(shift: shift, startedAt: at(3_600))
        context.insert(open)
        try shift.end(at: at(4 * 3600))
        try context.save()

        let correction = try shift.pauseCorrection(from: at(3_600), to: at(5_400), replacing: open)
        #expect(throws: ShiftPauseCorrectionRefusal.pauseIsOpen) {
            try open.apply(correction)
        }
        #expect(open.endedAt == nil)
    }

    @Test("A correction reaching outside the shift is refused, and writes nothing")
    func refusesAStretchOutsideTheShift() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)
        let service = corrections(context)

        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.startsBeforeShift)) {
            try service.correct(pause, from: at(-60), to: at(600))
        }
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.endsAfterShift)) {
            try service.correct(pause, from: at(3_600), to: at(4 * 3600 + 60))
        }

        #expect(pause.startedAt == at(3_600))
        #expect(pause.endedAt == at(5_400))
        #expect(!context.hasChanges)
    }

    @Test("A correction of no length is refused")
    func refusesAZeroLengthCorrection() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)

        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.notPositiveDuration)) {
            try corrections(context).correct(pause, from: at(3_600), to: at(3_600))
        }
        #expect(shift.completedPausedTime?.duration == 1_800)
    }

    @Test("A correction onto another recorded pause is refused rather than merged")
    func refusesAnOverlapWithAnotherPause() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        try shifts.pauseActiveShift(at: at(9_000))
        try shifts.resumeActiveShift(at: at(10_800))
        try shifts.endActiveShift(at: at(4 * 3600))

        let first = try #require(shift.pausesInOrder.first)
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.overlapsAnotherPause)) {
            try corrections(context).correct(first, from: at(3_600), to: at(9_600))
        }

        #expect(shift.pauses.count == 2, "Neither row was merged into the other")
        #expect(first.endedAt == at(5_400))
        #expect(shift.completedPausedTime?.duration == 3_600)
    }

    @Test("A pause may be corrected to touch the one after it")
    func allowsACorrectionTouchingTheNextPause() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        try shifts.pauseActiveShift(at: at(9_000))
        try shifts.resumeActiveShift(at: at(10_800))
        try shifts.endActiveShift(at: at(4 * 3600))

        let first = try #require(shift.pausesInOrder.first)
        try corrections(context).correct(first, from: at(3_600), to: at(9_000))

        #expect(shift.pauses.count == 2, "Two adjacent breaks stay two records")
        #expect(
            shift.completedPausedTime?.duration == 7_200,
            "The union runs them together into one continuous stretch, which is what they are"
        )
    }

    @Test("A correction that would swallow a delivery is refused rather than shortening the delivery")
    func refusesAnOverlapWithDeliveryWork() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(600))
        try deliveries.markArrivedAtPickup(delivery, at: at(900))
        try deliveries.markPickedUp(delivery, at: at(1_200))
        try deliveries.markDelivered(delivery, at: at(2_400))
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        try shifts.endActiveShift(at: at(4 * 3600))

        let pause = try onlyPause(of: shift)
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.overlapsDeliveryWork)) {
            try corrections(context).correct(pause, from: at(1_800), to: at(5_400))
        }

        // The delivery is the fact that was protected, so it is the fact the
        // refusal has to leave alone.
        #expect(delivery.acceptedAt == at(600))
        #expect(delivery.deliveredAt == at(2_400))
        #expect(shift.deliveryActiveTime().duration == 1_800)
        #expect(pause.startedAt == at(3_600))
        #expect(!context.hasChanges)
    }

    @Test("A missed pause overlapping delivery work is refused too")
    func refusesAMissedPauseOverDeliveryWork() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(600))
        try deliveries.markArrivedAtPickup(delivery, at: at(900))
        try deliveries.markPickedUp(delivery, at: at(1_200))
        try deliveries.markDelivered(delivery, at: at(2_400))
        try shifts.endActiveShift(at: at(4 * 3600))

        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.overlapsDeliveryWork)) {
            try corrections(context).addMissedPause(on: shift, from: at(1_200), to: at(1_800))
        }
        #expect(shift.pauses.isEmpty)
        #expect(!context.hasChanges)
    }

    @Test("A pause may be added in the gap between two deliveries")
    func addsAMissedPauseBetweenDeliveries() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let first = try deliveries.startDelivery(at: at(600))
        try deliveries.markArrivedAtPickup(first, at: at(900))
        try deliveries.markPickedUp(first, at: at(1_200))
        try deliveries.markDelivered(first, at: at(2_400))
        let second = try deliveries.startDelivery(at: at(9_000))
        try deliveries.markArrivedAtPickup(second, at: at(9_300))
        try deliveries.markPickedUp(second, at: at(9_600))
        try deliveries.markDelivered(second, at: at(10_800))
        try shifts.endActiveShift(at: at(4 * 3600))

        try corrections(context).addMissedPause(on: shift, from: at(3_600), to: at(7_200))

        #expect(shift.completedPausedTime?.duration == 3_600)
        #expect(
            shift.deliveryActiveTime().duration == seconds(3_600),
            "Delivery active time is what the deliveries say, and a pause beside them changes none of it"
        )
    }

    @Test("A pause that is no longer a row in the store is refused rather than half applied")
    func refusesAPauseTheStoreNoLongerHolds() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)
        let service = corrections(context)
        try service.delete(pause)

        #expect(throws: ShiftPauseCorrectionError.pauseNoLongerExists) {
            try service.correct(pause, from: at(3_600), to: at(4_200))
        }
        #expect(throws: ShiftPauseCorrectionError.pauseNoLongerExists) {
            try service.delete(pause)
        }
    }

    // MARK: What a correction must not move

    @Test("Elapsed time, delivery active time, mileage and gross earnings are all untouched")
    func nothingButThePausedFiguresMoves() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        let deliveries = DeliveryService(context: context)
        let delivery = try deliveries.startDelivery(at: at(600))
        try deliveries.markArrivedAtPickup(delivery, at: at(900))
        try deliveries.markPickedUp(delivery, at: at(1_200))
        try deliveries.markDelivered(delivery, at: at(2_400))
        try deliveries.setGrossEarnings(Money(minorUnits: 950), on: delivery)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(5_400))
        try shifts.endActiveShift(at: at(4 * 3600))
        try shifts.setGrossEarnings(Money(minorUnits: 8_000), on: shift)

        let distance = RouteDistance(
            metres: 32_186,
            segmentCount: 2,
            gapCount: 1,
            usableSampleCount: 120,
            usesInferredContinuity: false
        )
        let before = shift.metrics(for: distance)

        try corrections(context).correct(try onlyPause(of: shift), from: at(3_600), to: at(4_500))

        let after = shift.metrics(for: distance)

        // Moved, and by exactly the corrected pause.
        #expect(before.workingDuration == seconds(4 * 3600 - 1_800))
        #expect(after.workingDuration == seconds(4 * 3600 - 900))
        #expect(before.grossPerWorkingHour.amount != after.grossPerWorkingHour.amount)

        // Not moved. Every one of these is derived from a fact a pause does not
        // touch.
        #expect(after.elapsedDuration == before.elapsedDuration)
        #expect(after.elapsedDuration == seconds(4 * 3600))
        #expect(after.deliveryActiveTime == before.deliveryActiveTime)
        #expect(after.recordedDistance == before.recordedDistance)
        #expect(after.grossPerDeliveryActiveHour.amount == before.grossPerDeliveryActiveHour.amount)
        #expect(after.grossPerRecordedMile.amount == before.grossPerRecordedMile.amount)
        #expect(shift.grossEarnings == Money(minorUnits: 8_000))
        #expect(delivery.grossEarnings == Money(minorUnits: 950))
        #expect(delivery.deliveredAt == at(2_400))
    }

    @Test("Gross per working hour follows the corrected pause, and nothing else does")
    func theHourlyRateFollowsTheCorrection() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(7_200))
        try shifts.endActiveShift(at: at(4 * 3600))
        // $90 over a four-hour shift with an hour paused is $30.00 an hour.
        try shifts.setGrossEarnings(Money(minorUnits: 9_000), on: shift)

        #expect(shift.metrics(for: .none).grossPerWorkingHour.amount == Money(minorUnits: 3_000))

        // Corrected to a two-hour pause: two working hours, and $45.00 an hour.
        try corrections(context).correct(try onlyPause(of: shift), from: at(3_600), to: at(10_800))

        #expect(shift.completedWorkingDuration == seconds(2 * 3600))
        #expect(shift.metrics(for: .none).grossPerWorkingHour.amount == Money(minorUnits: 4_500))
        #expect(shift.metrics(for: .none).elapsedDuration == seconds(4 * 3600), "Elapsed time did not move")
    }

    @Test("A route recorded during the shift keeps every position, its segments and its gaps")
    func theRouteIsUntouched() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        // Two capture sessions with a break between them, which is what a
        // recorded pause really leaves in a route.
        let before = UUID()
        let after = UUID()
        for offset in stride(from: 0.0, through: 3_000, by: 60) {
            context.insert(
                RouteSample(
                    shift: shift,
                    sample: SyntheticRoute.sample(at: at(offset), northMetres: offset),
                    captureSessionID: before
                )
            )
        }
        for offset in stride(from: 5_400.0, through: 8_400, by: 60) {
            context.insert(
                RouteSample(
                    shift: shift,
                    sample: SyntheticRoute.sample(at: at(offset), northMetres: offset),
                    captureSessionID: after
                )
            )
        }
        try context.save()

        let distanceBefore = shift.recordedDistance()
        let countBefore = shift.routeSampleCount
        let sessionsBefore = Set(shift.routeSamples().map(\.captureSessionID))
        let timestampsBefore = shift.routeSamples().map(\.timestamp)
        let coordinatesBefore = shift.routeSamples().map { [$0.latitude, $0.longitude] }

        #expect(distanceBefore.segmentCount == 2, "The pause left a real break in the route")
        #expect(distanceBefore.gapCount > 0)

        try corrections(context).correct(try onlyPause(of: shift), from: at(3_600), to: at(4_500))
        // And a pause added over a stretch that really was recorded, which is
        // the case that cannot be made consistent without deleting positions.
        try corrections(context).addMissedPause(on: shift, from: at(6_000), to: at(7_200))

        #expect(shift.routeSampleCount == countBefore, "No position was created or deleted")
        let distanceAfter = shift.recordedDistance()
        #expect(
            distanceAfter == distanceBefore,
            "Recorded mileage, segments and gaps are all exactly as they were"
        )
        #expect(Set(shift.routeSamples().map(\.captureSessionID)) == sessionsBefore, "No session was rewritten")
        #expect(shift.routeSamples().map(\.timestamp) == timestampsBefore, "No position was retimed")
        #expect(shift.routeSamples().map { [$0.latitude, $0.longitude] } == coordinatesBefore)
    }

    // MARK: Period aggregates

    @Test("A period's working hours and the rate over them follow the correction")
    func thePeriodAggregateFollowsTheCorrection() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.pauseActiveShift(at: at(3_600))
        try shifts.resumeActiveShift(at: at(7_200))
        try shifts.endActiveShift(at: at(4 * 3600))
        try shifts.setGrossEarnings(Money(minorUnits: 9_000), on: shift)

        let before = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)
        #expect(before.workingDuration == seconds(3 * 3600))
        #expect(before.grossPerWorkingHour.amount == Money(minorUnits: 3_000))

        try corrections(context).delete(try onlyPause(of: shift))

        let after = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)
        #expect(after.workingDuration == seconds(4 * 3600), "The deleted pause stopped being subtracted")
        #expect(after.grossPerWorkingHour.amount == Money(minorUnits: 2_250))
        #expect(
            after.recordedGrossEarnings == before.recordedGrossEarnings,
            "The period's headline earnings do not move"
        )
        #expect(after.workingCoverage == before.workingCoverage, "and neither does its coverage")
    }

    @Test("An added pause shortens the period's working hours by exactly its length")
    func anAddedPauseReachesThePeriod() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(4 * 3600))
        try shifts.setGrossEarnings(Money(minorUnits: 9_000), on: shift)

        try corrections(context).addMissedPause(on: shift, from: at(3_600), to: at(7_200))

        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: day)
        #expect(metrics.workingDuration == seconds(3 * 3600))
        #expect(metrics.grossPerWorkingHour.amount == Money(minorUnits: 3_000))
        #expect(metrics.completedShiftCount == 1, "The shift is still one completed shift, in the same period")
    }

    // MARK: Malformed stored pauses

    @Test("Overlapping stored pauses stay measurable, and correcting one does not merge them")
    func aPreExistingOverlapIsStillMeasured() throws {
        // Two overlapping rows, which the services cannot write. The union is
        // the defence against them and it is not weakened by this feature: the
        // editor refuses to *create* an overlap, and a store that already holds
        // one is still measured as the stretch it covers rather than as the sum
        // of two rows.
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let first = ShiftPause(shift: shift, startedAt: at(3_600), endedAt: at(7_200))
        let second = ShiftPause(shift: shift, startedAt: at(5_400), endedAt: at(9_000))
        context.insert(first)
        context.insert(second)
        try shift.end(at: at(4 * 3600))
        try context.save()

        #expect(shift.completedPausedTime?.duration == 5_400, "Unioned, not summed")
        #expect(shift.completedPausedTime?.intervalCount == 2)

        // The second row can still be corrected out of the overlap, which is the
        // repair the editor offers for a store like this.
        try corrections(context).correct(second, from: at(7_200), to: at(9_000))

        #expect(shift.pauses.count == 2, "Nothing was merged")
        #expect(shift.completedPausedTime?.duration == 5_400)
        #expect(shift.completedWorkingDuration == seconds(4 * 3600 - 5_400))
    }

    @Test("A malformed stored pause can be corrected into a measurable one")
    func aMalformedRowCanBeRepaired() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        let backwards = ShiftPause(shift: shift, startedAt: at(7_200), endedAt: at(3_600))
        context.insert(backwards)
        try shift.end(at: at(4 * 3600))
        try context.save()

        #expect(shift.completedPausedTime?.unusableIntervalCount == 1)
        #expect(shift.completedPausedTime?.duration == 0)

        try corrections(context).correct(backwards, from: at(3_600), to: at(7_200))

        #expect(shift.completedPausedTime?.unusableIntervalCount == 0)
        #expect(shift.completedPausedTime?.duration == 3_600)
    }

    // MARK: A refused save

    @Test("A refused correction leaves the store holding exactly the pause it had")
    func aRefusedCorrectionRollsBack() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try pausedShift(in: context)
        let shiftID = shift.id

        #expect(throws: ShiftPauseCorrectionError.storeUnavailable(underlying: RefusedPauseSave())) {
            try refusing(context).correct(try onlyPause(of: shift), from: at(600), to: at(1_200))
        }

        #expect(!context.hasChanges, "The rollback left nothing pending")

        // Read fresh: a rollback restores the store rather than the value the
        // live object is holding, and the store is what a relaunch would show.
        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.pauses.count == 1)
        #expect(stored.pausesInOrder.first?.startedAt == at(3_600), "The exact pause the store had")
        #expect(stored.pausesInOrder.first?.endedAt == at(5_400))
        #expect(stored.completedWorkingDuration == seconds(4 * 3600 - 1_800))
    }

    @Test("A refused deletion leaves the pause in the store")
    func aRefusedDeletionRollsBack() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try pausedShift(in: context)
        let shiftID = shift.id

        #expect(throws: ShiftPauseCorrectionError.storeUnavailable(underlying: RefusedPauseSave())) {
            try refusing(context).delete(try onlyPause(of: shift))
        }

        #expect(!context.hasChanges)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.pauses.count == 1)
        #expect(stored.pausesInOrder.first?.startedAt == at(3_600))
        #expect(stored.pausesInOrder.first?.endedAt == at(5_400))
    }

    @Test("A refused addition leaves the shift with no pause at all")
    func aRefusedAdditionRollsBack() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(4 * 3600))
        let shiftID = shift.id

        #expect(throws: ShiftPauseCorrectionError.storeUnavailable(underlying: RefusedPauseSave())) {
            try refusing(context).addMissedPause(on: shift, from: at(3_600), to: at(5_400))
        }

        #expect(!context.hasChanges)

        let reopened = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try reopened.fetch(FetchDescriptor<Shift>()).first { $0.id == shiftID })

        #expect(stored.pauses.isEmpty, "No half-inserted row outlived the refused save")
        #expect(try reopened.fetch(FetchDescriptor<ShiftPause>()).isEmpty)
        #expect(stored.completedWorkingDuration == seconds(4 * 3600))
    }

    // MARK: Asking without writing

    @Test("The editor can ask what a stretch would be refused for without attempting it")
    func refusalIsAskableWithoutWriting() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        let pause = try onlyPause(of: shift)
        let service = corrections(context)

        #expect(service.refusal(correcting: pause, on: shift, from: at(3_600), to: at(3_000)) == .notPositiveDuration)
        #expect(service.refusal(correcting: pause, on: shift, from: at(-60), to: at(600)) == .startsBeforeShift)
        #expect(service.refusal(correcting: pause, on: shift, from: at(3_600), to: at(4_500)) == nil)
        // The pause being corrected never collides with itself.
        #expect(service.refusal(correcting: pause, on: shift, from: at(3_600), to: at(5_400)) == nil)
        #expect(pause.startedAt == at(3_600), "Asking wrote nothing")
        #expect(!context.hasChanges)
    }

    // MARK: The export

    private func exportedShift(_ shift: Shift) throws -> [String: Any] {
        let document = ExportDocument(
            scope: .shift(shift.id),
            shifts: [try shift.exportRecord(for: .none)],
            summary: nil,
            exportedAt: start
        )
        let parsed = try JSONSerialization.jsonObject(with: try ExportDocumentEncoder().json(for: document))
        let object = try #require(parsed as? [String: Any])
        let shifts = try #require(object["shifts"] as? [[String: Any]])
        return try #require(shifts.first)
    }

    @Test("JSON carries a corrected pause through the fields it already has")
    func jsonCarriesTheCorrection() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)

        let before = try exportedShift(shift)
        #expect(before["pausedSeconds"] as? Int == 1_800)
        #expect(before["workingSeconds"] as? Int == 4 * 3600 - 1_800)
        #expect(before["pauseCount"] as? Int == 1)

        try corrections(context).correct(try onlyPause(of: shift), from: at(3_600), to: at(4_500))

        let after = try exportedShift(shift)
        #expect(after["pausedSeconds"] as? Int == 900)
        #expect(after["workingSeconds"] as? Int == 4 * 3600 - 900)
        #expect(after["pauseCount"] as? Int == 1, "One pause, corrected, not two")
        // Untouched by the correction, and written from the same record.
        #expect(after["elapsedSeconds"] as? Int == 4 * 3600)
        #expect(after["startedAt"] as? String == ExportTimestamp.string(start))
        #expect(after["endedAt"] as? String == ExportTimestamp.string(at(4 * 3600)))
    }

    @Test("A deleted pause exports as zero paused seconds and no pause, never as a missing value")
    func jsonCarriesTheDeletion() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)

        try corrections(context).delete(try onlyPause(of: shift))

        let exported = try exportedShift(shift)
        #expect(exported["pauseCount"] as? Int == 0)
        // Zero rather than null: a shift with no pause really was paused for no
        // time, which is the distinction `ExportFormat` version 3 established.
        #expect(exported["pausedSeconds"] as? Int == 0)
        #expect(exported["workingSeconds"] as? Int == 4 * 3600)
        #expect(exported["elapsedSeconds"] as? Int == 4 * 3600)
    }

    @Test("The export format version is unmoved, because no field changed meaning")
    func theFormatVersionIsUnmoved() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        try corrections(context).correct(try onlyPause(of: shift), from: at(3_600), to: at(4_500))

        let document = ExportDocument(
            scope: .shift(shift.id),
            shifts: [try shift.exportRecord(for: .none)],
            summary: nil,
            exportedAt: start
        )
        let parsed = try JSONSerialization.jsonObject(with: try ExportDocumentEncoder().json(for: document))
        let object = try #require(parsed as? [String: Any])

        // `pausedSeconds`, `workingSeconds` and `pauseCount` already carried
        // exactly this. Nothing was added, removed, renamed or redefined.
        #expect(object["formatVersion"] as? Int == 4)
        #expect(ExportFormat.version == 4)
    }

    @Test("CSV says the same thing through the columns it already has")
    func csvCarriesTheCorrection() throws {
        let context = try makeContext()
        let shift = try pausedShift(in: context)
        try corrections(context).addMissedPause(on: shift, from: at(9_000), to: at(10_800))

        let document = ExportDocument(
            scope: .allHistory,
            shifts: [try shift.exportRecord(for: .none)],
            summary: nil,
            exportedAt: start
        )
        let text = String(decoding: try ExportDocumentEncoder().csv(for: document), as: UTF8.self)
        let records = text.split(separator: "\r\n", omittingEmptySubsequences: true).map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        let header = try #require(records.first)
        #expect(header.count == 36, "No column was added for pause editing")
        let row = try #require(records.dropFirst().first.map { Dictionary(uniqueKeysWithValues: zip(header, $0)) })

        #expect(row["shiftPauseCount"] == "2")
        #expect(row["shiftPausedSeconds"] == "3600")
        #expect(row["shiftWorkingSeconds"] == "\(4 * 3600 - 3_600)")
        #expect(row["shiftElapsedSeconds"] == "\(4 * 3600)")
    }

    // MARK: Time zones and daylight saving

    /// A pause corrected across a spring-forward measures the real hour, not the
    /// two the wall clock appears to show.
    ///
    /// The whole feature works in instants: the pickers produce `Date` values,
    /// the bounds compare them, and the union measures the seconds between them.
    /// This pins that, because the obvious wrong implementation — subtracting
    /// clock components — reports the pause below as two hours and the shift as
    /// having worked an hour less than it did.
    @Test("A pause corrected across a spring-forward measures real elapsed time")
    func measuresAcrossASpringForward() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        // 8 March 2026: 02:00 does not exist, so midnight to 06:00 is five real
        // hours rather than six.
        func local(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(
                newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: hour, minute: minute))
            )
        }

        let shiftStart = try local(0)
        let shiftEnd = try local(6)
        #expect(shiftEnd.timeIntervalSince(shiftStart) == seconds(5 * 3600), "The shift itself spans five real hours")

        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: shiftStart)
        try shifts.pauseActiveShift(at: try local(4))
        try shifts.resumeActiveShift(at: try local(5))
        try shifts.endActiveShift(at: shiftEnd)

        // Corrected to 01:30 through 03:30 local, which crosses the missing hour
        // and is one real hour.
        try corrections(context).correct(try onlyPause(of: shift), from: try local(1, 30), to: try local(3, 30))

        #expect(shift.completedPausedTime?.duration == 3_600, "Two wall-clock hours, one real one")
        #expect(shift.completedDuration == seconds(5 * 3600))
        #expect(shift.completedWorkingDuration == seconds(4 * 3600))
    }

    @Test("A pause corrected across a fall-back measures real elapsed time too")
    func measuresAcrossAFallBack() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        // 1 November 2026: 01:00 through 02:00 happens twice, so midnight to
        // 06:00 is seven real hours.
        func local(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(
                newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: hour, minute: minute))
            )
        }

        let shiftStart = try local(0)
        let shiftEnd = try local(6)
        #expect(shiftEnd.timeIntervalSince(shiftStart) == 7 * 3600)

        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: shiftStart)
        try shifts.endActiveShift(at: shiftEnd)

        // 00:30 through 03:30 local covers the repeated hour: three wall-clock
        // hours, four real ones.
        try corrections(context).addMissedPause(on: shift, from: try local(0, 30), to: try local(3, 30))

        #expect(shift.completedPausedTime?.duration == seconds(4 * 3600))
        #expect(shift.completedWorkingDuration == seconds(3 * 3600))
    }

    @Test("A stretch outside the shift is refused on the instants, whatever the wall clock reads")
    func boundsAreCheckedOnInstantsAcrossADSTChange() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        func local(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(
                newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: hour, minute: minute))
            )
        }

        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: try local(1))
        try shifts.endActiveShift(at: try local(4))

        // 00:30 local is before the shift began even though the shift looks only
        // three clock hours long and this looks half an hour before it.
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.startsBeforeShift)) {
            try corrections(context).addMissedPause(on: shift, from: try local(0, 30), to: try local(3))
        }
        #expect(throws: ShiftPauseCorrectionError.invalidCorrection(.endsAfterShift)) {
            try corrections(context).addMissedPause(on: shift, from: try local(3), to: try local(5))
        }
        #expect(shift.pauses.isEmpty)
    }
}
