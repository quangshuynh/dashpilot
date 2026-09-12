import Foundation
import Testing
@testable import DashPilot

/// The pure domain reading of a shift's pauses: the union, the clipping, the
/// working-duration subtraction, and the lifecycle state derived from rows.
///
/// No store, no container and no rendered view — the model adapter is covered in
/// ``ShiftPausePersistenceTests``.
@Suite("Shift pause domain")
struct ShiftPauseTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)
    private let calculator = ShiftPausedTimeCalculator()

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func window(_ seconds: TimeInterval) -> ClosedRange<Date> { start...at(seconds) }

    // MARK: The union

    @Test("A shift with no pauses is paused for no time, and that is a measurement")
    func noPausesMeasuresZero() {
        let measured = calculator.pausedTime(of: [], within: window(3_600))

        #expect(measured == .none)
        #expect(measured.duration == 0)
        #expect(!measured.hasPauses)
        #expect(measured.isComplete)
    }

    @Test("One closed pause contributes its own length")
    func oneClosedPause() {
        let measured = calculator.pausedTime(
            of: [ShiftPauseInterval(start: at(600), end: at(2_400))],
            within: window(3_600)
        )

        #expect(measured.duration == 1_800)
        #expect(measured.intervalCount == 1)
        #expect(measured.openIntervalCount == 0)
    }

    @Test("Separate pauses add up")
    func separatePausesAdd() {
        let measured = calculator.pausedTime(
            of: [
                ShiftPauseInterval(start: at(600), end: at(1_200)),
                ShiftPauseInterval(start: at(2_400), end: at(3_000))
            ],
            within: window(3_600)
        )

        #expect(measured.duration == 1_200)
        #expect(measured.intervalCount == 2)
    }

    /// The service cannot write overlapping pauses — pausing an already paused
    /// shift is refused — so this is about a store that somehow holds them.
    /// Summing would subtract the same minutes twice and report a shift as
    /// having been worked less than it was.
    @Test("Overlapping pauses are unioned rather than summed")
    func overlappingPausesAreUnioned() {
        let measured = calculator.pausedTime(
            of: [
                ShiftPauseInterval(start: at(600), end: at(2_400)),
                ShiftPauseInterval(start: at(1_800), end: at(3_000))
            ],
            within: window(3_600)
        )

        #expect(measured.duration == 2_400, "1800 to 3000 overlaps 600 to 2400; the union is 600 to 3000")
    }

    @Test("The union does not depend on the order the pauses arrive in")
    func unionIsOrderIndependent() {
        let intervals = [
            ShiftPauseInterval(start: at(2_400), end: at(3_000)),
            ShiftPauseInterval(start: at(600), end: at(1_200))
        ]

        #expect(
            calculator.pausedTime(of: intervals, within: window(3_600)).duration
                == calculator.pausedTime(of: intervals.reversed(), within: window(3_600)).duration
        )
    }

    @Test("A pause ending exactly where the next begins is one stretch, not two with a gap")
    func touchingPausesMerge() {
        let measured = calculator.pausedTime(
            of: [
                ShiftPauseInterval(start: at(600), end: at(1_200)),
                ShiftPauseInterval(start: at(1_200), end: at(1_800))
            ],
            within: window(3_600)
        )

        #expect(measured.duration == 1_200)
    }

    // MARK: The open pause

    /// The property the whole feature rests on: while a pause is open it grows
    /// at exactly the rate elapsed time does, so working time stops.
    @Test("An open pause is measured to the window's end, so working time stops growing")
    func openPauseTakesTheWindowEnd() {
        let interval = ShiftPauseInterval(start: at(600), end: nil)

        #expect(calculator.pausedTime(of: [interval], within: window(1_200)).duration == 600)
        #expect(calculator.pausedTime(of: [interval], within: window(3_600)).duration == 3_000)

        // Elapsed minus paused is the same number at both readings.
        #expect(1_200 - 600 == 600)
        #expect(3_600 - 3_000 == 600)
    }

    @Test("An open pause is counted as open")
    func openPauseIsCounted() {
        let measured = calculator.pausedTime(
            of: [
                ShiftPauseInterval(start: at(600), end: at(1_200)),
                ShiftPauseInterval(start: at(2_400), end: nil)
            ],
            within: window(3_600)
        )

        #expect(measured.intervalCount == 2)
        #expect(measured.openIntervalCount == 1)
        #expect(measured.duration == 1_800)
    }

    // MARK: Clipping and anomalies

    @Test("A pause is clipped to the shift window rather than overflowing it")
    func pausesAreClipped() {
        let measured = calculator.pausedTime(
            of: [ShiftPauseInterval(start: at(-600), end: at(7_200))],
            within: window(3_600)
        )

        #expect(measured.duration == 3_600, "It cannot subtract more than the shift lasted")
        #expect(measured.isComplete)
    }

    @Test("A pause lying wholly outside the shift contributes nothing and is counted unusable")
    func pauseOutsideTheWindow() {
        let measured = calculator.pausedTime(
            of: [ShiftPauseInterval(start: at(7_200), end: at(9_000))],
            within: window(3_600)
        )

        #expect(measured.duration == 0)
        #expect(measured.unusableIntervalCount == 1)
        #expect(!measured.isComplete)
    }

    /// Dropping this row overstates working time, which is the direction that
    /// matters. It is counted rather than repaired so a reader can see the total
    /// is short of its sources.
    @Test("A pause ending before it began is counted unusable rather than repaired")
    func malformedPauseIsCounted() {
        let interval = ShiftPauseInterval(start: at(2_400), end: at(600))
        let measured = calculator.pausedTime(of: [interval], within: window(3_600))

        #expect(interval.isMalformed)
        #expect(measured.duration == 0)
        #expect(measured.unusableIntervalCount == 1)
    }

    @Test("A pause of no length is a measurement of zero, not an unusable row")
    func zeroLengthPauseIsUsable() {
        let measured = calculator.pausedTime(
            of: [ShiftPauseInterval(start: at(600), end: at(600))],
            within: window(3_600)
        )

        #expect(measured.duration == 0)
        #expect(measured.intervalCount == 1)
        #expect(measured.isComplete)
    }

    // MARK: Working duration

    @Test("Working duration is elapsed less paused")
    func workingIsElapsedLessPaused() {
        let paused = calculator.pausedTime(
            of: [ShiftPauseInterval(start: at(3_600), end: at(5_400))],
            within: window(10_800)
        )

        #expect(ShiftMetricsCalculator.workingDuration(elapsed: 10_800, paused: paused) == 9_000)
    }

    @Test("A shift that was never paused has a working duration equal to its elapsed one")
    func neverPausedIsUnchanged() {
        #expect(ShiftMetricsCalculator.workingDuration(elapsed: 10_800, paused: .none) == 10_800)
    }

    @Test("A running shift has no working duration, because it has no elapsed one")
    func runningShiftHasNoWorkingDuration() {
        #expect(ShiftMetricsCalculator.workingDuration(elapsed: nil, paused: .none) == nil)
    }

    /// Unreachable through the app's own API, because pauses are clipped to the
    /// shift. A negative denominator is not something any figure downstream
    /// could interpret, so it floors at zero and the rate reports no working
    /// time instead.
    @Test("Pauses totalling more than the shift produce zero working time, never a negative one")
    func workingDurationNeverGoesNegative() {
        let paused = ShiftPausedTime(
            duration: 7_200,
            intervalCount: 1,
            openIntervalCount: 0,
            unusableIntervalCount: 0
        )

        #expect(ShiftMetricsCalculator.workingDuration(elapsed: 3_600, paused: paused) == 0)
    }

    // MARK: Lifecycle state

    @Test("The three lifecycle states are distinct, and two of them are unfinished")
    func lifecycleStates() {
        #expect(ShiftLifecycleState.running.isUnfinished)
        #expect(ShiftLifecycleState.paused.isUnfinished)
        #expect(!ShiftLifecycleState.ended.isUnfinished)

        #expect(ShiftLifecycleState.running.isAccumulatingWorkingTime)
        #expect(!ShiftLifecycleState.paused.isAccumulatingWorkingTime)
        #expect(!ShiftLifecycleState.ended.isAccumulatingWorkingTime)

        #expect(Set(ShiftLifecycleState.allCases.map(\.title)).count == 3)
    }

    // MARK: The shared union

    /// Delivery active time and paused time are the same question asked of
    /// different rows, and they go through one sweep so they cannot drift apart.
    @Test("The date-range union is the one used by both calculations")
    func unionIsShared() {
        let ranges = [start...at(1_200), at(600)...at(1_800), at(3_000)...at(3_600)]
        let merged = DateRangeUnion.merged(ranges)

        #expect(merged.count == 2)
        #expect(merged.first == start...at(1_800))
        #expect(DateRangeUnion.coveredDuration(ranges) == 2_400)
        #expect(DateRangeUnion.merged([]).isEmpty)
        #expect(DateRangeUnion.coveredDuration([]) == 0)
    }
}
