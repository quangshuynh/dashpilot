import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Shift earnings")
struct ShiftEarningsTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    private func completedShift() throws -> Shift {
        let shift = Shift(startedAt: start)
        try shift.end(at: start.addingTimeInterval(3600))
        return shift
    }

    // MARK: The model's rules

    @Test("A new shift has no earnings, which is not an amount of zero")
    func startsWithNoEarnings() throws {
        let shift = try completedShift()

        #expect(shift.grossEarnings == nil)
        #expect(shift.grossEarnings != Money.zero)
    }

    @Test("A completed shift records what it paid, exactly as entered")
    func recordsEarnings() throws {
        let shift = try completedShift()
        let earnings = try #require(Money(exact: "86.25"))

        try shift.setGrossEarnings(earnings)

        #expect(shift.grossEarnings == earnings)
        #expect(shift.grossEarnings?.amount == Decimal(string: "86.25"))
    }

    @Test("A running shift cannot record earnings")
    func refusesEarningsWhileRunning() throws {
        let shift = Shift(startedAt: start)
        let earnings = try #require(Money(exact: "86.25"))

        #expect(throws: ShiftError.shiftNotCompleted) {
            try shift.setGrossEarnings(earnings)
        }
        #expect(shift.grossEarnings == nil, "A refused entry stores nothing")
    }

    @Test("Negative earnings are refused")
    func refusesNegativeEarnings() throws {
        let shift = try completedShift()
        let negative = try #require(Money(exact: "-1.00"))

        #expect(throws: ShiftError.negativeEarnings) {
            try shift.setGrossEarnings(negative)
        }
        #expect(shift.grossEarnings == nil)
    }

    @Test("Zero is an amount a driver may record")
    func recordsZero() throws {
        let shift = try completedShift()

        try shift.setGrossEarnings(.zero)

        #expect(shift.grossEarnings == Money.zero)
        #expect(shift.grossEarnings != nil, "Recording nothing earned is not the same as recording nothing")
    }

    @Test("Editing replaces the previous amount rather than adding to it")
    func editReplaces() throws {
        let shift = try completedShift()
        try shift.setGrossEarnings(try #require(Money(exact: "86.25")))

        try shift.setGrossEarnings(try #require(Money(exact: "104.10")))

        #expect(shift.grossEarnings == Money(exact: "104.10"))
    }

    @Test("A refused edit leaves the stored amount untouched")
    func refusedEditKeepsTheStoredAmount() throws {
        let shift = try completedShift()
        let recorded = try #require(Money(exact: "86.25"))
        try shift.setGrossEarnings(recorded)

        #expect(throws: ShiftError.negativeEarnings) {
            try shift.setGrossEarnings(try #require(Money(exact: "-5.00")))
        }

        #expect(shift.grossEarnings == recorded)
    }

    @Test("Removing earnings returns the shift to having none, not to zero")
    func removesEarnings() throws {
        let shift = try completedShift()
        try shift.setGrossEarnings(try #require(Money(exact: "86.25")))

        shift.clearGrossEarnings()

        #expect(shift.grossEarnings == nil)
    }

    @Test("Removing earnings a shift never had is harmless")
    func removingNothingIsHarmless() throws {
        let shift = try completedShift()

        shift.clearGrossEarnings()

        #expect(shift.grossEarnings == nil)
    }

    @Test("Amounts that binary floating point cannot represent survive exactly")
    func keepsExactDecimals() throws {
        let shift = try completedShift()
        let awkward = try #require(Money(exact: "0.10"))

        try shift.setGrossEarnings(awkward)

        let stored = try #require(shift.grossEarnings)
        #expect(stored + (try #require(Money(exact: "0.20"))) == Money(exact: "0.30"))
    }

    @Test("Earnings do not disturb the rest of the shift")
    func leavesTheShiftOtherwiseUnchanged() throws {
        let shift = try completedShift()

        try shift.setGrossEarnings(try #require(Money(exact: "86.25")))

        #expect(shift.startedAt == start)
        #expect(shift.completedDuration == 3600)
        #expect(!shift.isActive)
        #expect(shift.routeSamples.isEmpty)
    }

    // MARK: Through the service

    @Test("The service saves a recorded amount")
    func servicePersistsEarnings() throws {
        let context = try makeContext()
        let shift = try completedShift()
        context.insert(shift)
        try context.save()

        try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "86.25")), on: shift)

        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(stored.grossEarnings == Money(exact: "86.25"))
        #expect(!context.hasChanges, "The amount is committed, not left pending")
    }

    @Test("The service refuses to record earnings against a running shift")
    func serviceRefusesARunningShift() throws {
        let context = try makeContext()
        let running = Shift(startedAt: start)
        context.insert(running)
        try context.save()

        #expect(throws: ShiftLifecycleError.invalidTransition(.shiftNotCompleted)) {
            try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "86.25")), on: running)
        }
        #expect(running.grossEarnings == nil)
    }

    @Test("The service refuses a negative amount")
    func serviceRefusesNegativeEarnings() throws {
        let context = try makeContext()
        let shift = try completedShift()
        context.insert(shift)
        try context.save()

        #expect(throws: ShiftLifecycleError.invalidTransition(.negativeEarnings)) {
            try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "-0.01")), on: shift)
        }
        #expect(shift.grossEarnings == nil)
    }

    @Test("The service removes a recorded amount")
    func serviceRemovesEarnings() throws {
        let context = try makeContext()
        let shift = try completedShift()
        context.insert(shift)
        let service = ShiftService(context: context)
        try service.setGrossEarnings(try #require(Money(exact: "86.25")), on: shift)

        try service.clearGrossEarnings(on: shift)

        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(stored.grossEarnings == nil)
    }

    @Test("Both refusals can be explained to the driver")
    func refusalsAreExplained() {
        #expect(
            ShiftLifecycleError.invalidTransition(.shiftNotCompleted).errorDescription
                == "Earnings can be recorded once the shift has ended."
        )
        #expect(
            ShiftLifecycleError.invalidTransition(.negativeEarnings).errorDescription
                == "Gross earnings cannot be negative."
        )
    }

    @Test("Earnings belong to one shift only")
    func earningsAreScopedToOneShift() throws {
        let context = try makeContext()
        let paid = try completedShift()
        let unpaid = Shift(startedAt: start.addingTimeInterval(7200))
        try unpaid.end(at: start.addingTimeInterval(10_800))
        context.insert(paid)
        context.insert(unpaid)

        try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "86.25")), on: paid)

        #expect(paid.grossEarnings == Money(exact: "86.25"))
        #expect(unpaid.grossEarnings == nil)
    }
}
