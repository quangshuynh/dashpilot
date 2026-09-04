import Foundation
import Testing
@testable import DashPilot

@Suite("Shift lifecycle")
struct ShiftTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    @Test("A new shift is active and has no completed duration")
    func newShiftIsActive() {
        let shift = Shift(startedAt: start)

        #expect(shift.isActive)
        #expect(shift.endedAt == nil)
        #expect(shift.completedDuration == nil)
    }

    @Test("Elapsed time of a running shift is measured against the reference date")
    func elapsedWhileRunning() {
        let shift = Shift(startedAt: start)

        #expect(shift.elapsed(asOf: start) == 0)
        #expect(shift.elapsed(asOf: start.addingTimeInterval(5400)) == 5400)
    }

    @Test("Ending a shift fixes its duration")
    func endingFixesDuration() throws {
        let shift = Shift(startedAt: start)
        try shift.end(at: start.addingTimeInterval(3600))

        #expect(!shift.isActive)
        #expect(shift.completedDuration == 3600)
        // A later reference date no longer advances the elapsed time.
        #expect(shift.elapsed(asOf: start.addingTimeInterval(99_999)) == 3600)
    }

    @Test("A shift cannot be ended twice")
    func cannotEndTwice() throws {
        let shift = Shift(startedAt: start)
        try shift.end(at: start.addingTimeInterval(60))

        #expect(throws: ShiftError.alreadyEnded) {
            try shift.end(at: start.addingTimeInterval(120))
        }
        #expect(shift.completedDuration == 60)
    }

    @Test("A shift cannot end before it started")
    func cannotEndBeforeStart() {
        let shift = Shift(startedAt: start)

        #expect(throws: ShiftError.endPrecedesStart) {
            try shift.end(at: start.addingTimeInterval(-1))
        }
        #expect(shift.isActive)
    }

    @Test("A zero length shift is permitted")
    func zeroLengthShift() throws {
        let shift = Shift(startedAt: start)
        try shift.end(at: start)

        #expect(shift.completedDuration == 0)
    }

    @Test("A backwards clock reads as zero elapsed rather than a negative duration")
    func backwardsClockClampsToZero() {
        let shift = Shift(startedAt: start)

        #expect(shift.elapsed(asOf: start.addingTimeInterval(-600)) == 0)
    }
}
