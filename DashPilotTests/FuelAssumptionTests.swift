import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The assumptions a completed shift records its fuel estimate under: which
/// pairs the model accepts, what a refused edit leaves behind, and the property
/// the whole design exists for — **an older shift's estimate cannot move when a
/// newer one records something different.**
///
/// ## The claim this suite exists for
///
/// A fuel estimate is derived from three things, and two of them are
/// assumptions. If those two lived in one global place, every shift a driver had
/// ever worked would be re-costed the moment they changed vehicle or filled up
/// at a different price, and a history screen would quietly show different
/// numbers than it did yesterday. So each shift records its own pair, and the
/// tests below prove that recording, changing and removing one shift's pair
/// leaves every other shift exactly where it was.
///
/// ## And the rule beside it
///
/// **An edit moves both halves or neither.** A driver correcting a price and
/// mistyping an economy in the same edit keeps the pair they had.
///
/// Every figure, time and coordinate here is invented.
@MainActor
@Suite("Fuel assumptions")
struct FuelAssumptionTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private static let metresPerMile = 1_609.344

    /// The estimate's own miles back in metres, so a route measured in metres
    /// and an estimate stated in miles can be compared without a second
    /// conversion rule.
    private static func metres(_ miles: Decimal) -> Double {
        NSDecimalNumber(decimal: miles).doubleValue * metresPerMile
    }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory.makeInMemoryContainer())
    }

    private func completedShift(startedAt: Date? = nil) throws -> Shift {
        let shift = Shift(startedAt: startedAt ?? start)
        try shift.end(at: (startedAt ?? start).addingTimeInterval(4 * 3600))
        return shift
    }

    private func economy(_ value: String) throws -> Decimal {
        try #require(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }

    /// A measured route covering `miles`, with no detected gap.
    private func route(miles: Double) -> RouteDistance {
        RouteDistance(
            metres: miles * Self.metresPerMile,
            segmentCount: 1,
            gapCount: 0,
            usableSampleCount: 10,
            usesInferredContinuity: false
        )
    }

    // MARK: The model's rules


    @Test("A new shift records no assumptions, which is not a fuel economy of zero")
    func startsWithNone() throws {
        let shift = try completedShift()

        #expect(shift.fuelAssumptions == .none)
        #expect(shift.fuelAssumptions.hasAny == false)
        #expect(shift.fuelAssumptions.milesPerGallon != .zero)
    }

    @Test("A completed shift records both figures exactly as entered")
    func recordsBothFigures() throws {
        let shift = try completedShift()

        try shift.setFuelAssumptions(
            milesPerGallon: try economy("28.5"),
            gasPricePerGallon: Money(minorUnits: 329)
        )

        #expect(shift.fuelAssumptions.milesPerGallon == Decimal(string: "28.5"))
        #expect(shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 329))
        #expect(shift.fuelAssumptions.isComplete)
    }

    @Test("Each half is independently optional")
    func recordsOneHalfAlone() throws {
        let shift = try completedShift()

        try shift.setFuelAssumptions(milesPerGallon: try economy("28.5"), gasPricePerGallon: nil)

        #expect(shift.fuelAssumptions.hasAny)
        #expect(shift.fuelAssumptions.isComplete == false)
        #expect(shift.fuelEstimate(for: route(miles: 50)) == .unavailable(.gasPriceNotRecorded))
    }

    @Test("A running shift cannot record assumptions")
    func refusesWhileRunning() throws {
        let shift = Shift(startedAt: start)

        #expect(throws: ShiftError.shiftNotCompleted) {
            try shift.setFuelAssumptions(
                milesPerGallon: try self.economy("28.5"),
                gasPricePerGallon: Money(minorUnits: 329)
            )
        }
        #expect(shift.fuelAssumptions == .none, "A refused entry stores nothing")
    }

    @Test("A fuel economy of zero is refused, because it is the divisor")
    func refusesZeroEconomy() throws {
        let shift = try completedShift()

        #expect(throws: ShiftError.invalidFuelEconomy) {
            try shift.setFuelAssumptions(milesPerGallon: .zero, gasPricePerGallon: Money(minorUnits: 329))
        }
        #expect(shift.fuelAssumptions == .none)
    }

    @Test("A negative fuel economy is refused by the same rule")
    func refusesNegativeEconomy() throws {
        let shift = try completedShift()

        #expect(throws: ShiftError.invalidFuelEconomy) {
            try shift.setFuelAssumptions(milesPerGallon: Decimal(-5), gasPricePerGallon: nil)
        }
    }

    @Test("A negative gas price is refused, and a zero one is recorded")
    func gasPriceRules() throws {
        let shift = try completedShift()

        #expect(throws: ShiftError.negativeGasPrice) {
            try shift.setFuelAssumptions(
                milesPerGallon: try self.economy("25"),
                gasPricePerGallon: -Money(minorUnits: 100)
            )
        }
        #expect(shift.fuelAssumptions == .none)

        try shift.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: .zero)
        #expect(shift.fuelAssumptions.gasPricePerGallon == Money.zero)
        #expect(
            shift.fuelAssumptions.gasPricePerGallon != nil,
            "A recorded price of nothing is a fact, and is not the same as no price recorded"
        )
    }

    // MARK: Atomicity

    @Test("A refused edit leaves both halves exactly as they were")
    func refusedEditIsAtomic() throws {
        let shift = try completedShift()
        try shift.setFuelAssumptions(
            milesPerGallon: try economy("28.5"),
            gasPricePerGallon: Money(minorUnits: 329)
        )

        // A valid new price and an invalid new economy, in the one edit the
        // editor performs.
        #expect(throws: ShiftError.invalidFuelEconomy) {
            try shift.setFuelAssumptions(milesPerGallon: .zero, gasPricePerGallon: Money(minorUnits: 499))
        }

        #expect(shift.fuelAssumptions.milesPerGallon == Decimal(string: "28.5"))
        #expect(
            shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 329),
            "The valid half must not have landed while the invalid half was refused"
        )
    }

    @Test("A refused edit leaves the store with nothing pending")
    func refusedEditWritesNothing() throws {
        let context = try makeContext()
        let shift = try completedShift()
        context.insert(shift)
        try shift.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))
        try context.save()

        #expect(throws: ShiftError.negativeGasPrice) {
            try shift.setFuelAssumptions(
                milesPerGallon: try self.economy("30"),
                gasPricePerGallon: -Money(minorUnits: 200)
            )
        }

        #expect(context.hasChanges == false, "Nothing was written, so nothing is waiting to be saved")
        #expect(shift.fuelAssumptions.milesPerGallon == Decimal(25))
        #expect(shift.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 350))
    }

    @Test("Removing the assumptions leaves no estimate, rather than an estimate of nothing")
    func removalLeavesNoEstimate() throws {
        let shift = try completedShift()
        try shift.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))

        shift.clearFuelAssumptions()

        #expect(shift.fuelAssumptions == .none)
        #expect(shift.fuelEstimate(for: route(miles: 50)) == .unavailable(.milesPerGallonNotRecorded))
        #expect(shift.fuelEstimate(for: route(miles: 50)).cost != Money.zero)
    }

    // MARK: Historical stability

    @Test("Recording a different fuel economy on a newer shift does not move an older shift's estimate")
    func newerEconomyLeavesOlderShiftAlone() throws {
        let context = try makeContext()

        let older = try completedShift()
        context.insert(older)
        try older.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))

        let before = older.fuelEstimate(for: route(miles: 50))
        #expect(before.cost == Money(minorUnits: 700))

        // The driver changes vehicle and records the new figure on this week's
        // shift. There is no global fuel economy for the older shift to follow.
        let newer = try completedShift(startedAt: start.addingTimeInterval(7 * 24 * 3600))
        context.insert(newer)
        try newer.setFuelAssumptions(milesPerGallon: try economy("40"), gasPricePerGallon: Money(minorUnits: 350))
        try context.save()

        #expect(older.fuelAssumptions.milesPerGallon == Decimal(25))
        #expect(older.fuelEstimate(for: route(miles: 50)) == before)
        let newerCost = try #require(newer.fuelEstimate(for: route(miles: 50)).cost)
        #expect(newerCost.amount == Decimal(string: "4.375"), "50 miles at 40 mpg is 1.25 gallons, at $3.50")
        #expect(newerCost.rounded() == Money(minorUnits: 438), "Rounded once, for display")
    }

    @Test("Recording a different gas price on a newer shift does not move an older shift's estimate")
    func newerPriceLeavesOlderShiftAlone() throws {
        let context = try makeContext()

        let older = try completedShift()
        context.insert(older)
        try older.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))
        let before = older.fuelEstimate(for: route(miles: 50))

        let newer = try completedShift(startedAt: start.addingTimeInterval(7 * 24 * 3600))
        context.insert(newer)
        try newer.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 499))
        try context.save()

        #expect(older.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 350))
        #expect(older.fuelEstimate(for: route(miles: 50)) == before)
        #expect(newer.fuelEstimate(for: route(miles: 50)).cost == Money(minorUnits: 998), "2 gallons at $4.99")
    }

    @Test("Correcting one shift's assumptions moves that shift alone")
    func correctingOneShiftMovesOnlyIt() throws {
        let context = try makeContext()

        let older = try completedShift()
        let newer = try completedShift(startedAt: start.addingTimeInterval(7 * 24 * 3600))
        for shift in [older, newer] {
            context.insert(shift)
            try shift.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))
        }
        try context.save()

        try newer.setFuelAssumptions(milesPerGallon: try economy("50"), gasPricePerGallon: Money(minorUnits: 350))
        try context.save()

        #expect(older.fuelEstimate(for: route(miles: 50)).cost == Money(minorUnits: 700))
        #expect(newer.fuelEstimate(for: route(miles: 50)).cost == Money(minorUnits: 350))
    }

    // MARK: The default is the last pair recorded, and it is a suggestion only

    @Test("The most recent completed shift that recorded assumptions supplies the default")
    func defaultIsTheMostRecentRecordedPair() throws {
        let context = try makeContext()
        let service = ShiftService(context: context)

        #expect(service.mostRecentFuelAssumptions() == .none, "With nothing recorded there is no default")

        let older = try completedShift()
        context.insert(older)
        try older.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))

        let newer = try completedShift(startedAt: start.addingTimeInterval(7 * 24 * 3600))
        context.insert(newer)
        try newer.setFuelAssumptions(milesPerGallon: try economy("40"), gasPricePerGallon: Money(minorUnits: 499))
        try context.save()

        let mostRecent = service.mostRecentFuelAssumptions()
        #expect(mostRecent.milesPerGallon == Decimal(40))
        #expect(mostRecent.gasPricePerGallon == Money(minorUnits: 499))
    }

    @Test("A shift recording no assumptions is skipped rather than answering the default")
    func defaultSkipsShiftsWithoutAssumptions() throws {
        let context = try makeContext()

        let recorded = try completedShift()
        context.insert(recorded)
        try recorded.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))

        context.insert(try completedShift(startedAt: start.addingTimeInterval(7 * 24 * 3600)))
        try context.save()

        #expect(ShiftService(context: context).mostRecentFuelAssumptions().milesPerGallon == Decimal(25))
    }

    @Test("A running shift never supplies the default, because it cannot record assumptions")
    func defaultIgnoresRunningShifts() throws {
        let context = try makeContext()

        let recorded = try completedShift()
        context.insert(recorded)
        try recorded.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))
        context.insert(Shift(startedAt: start.addingTimeInterval(7 * 24 * 3600)))
        try context.save()

        #expect(ShiftService(context: context).mostRecentFuelAssumptions().milesPerGallon == Decimal(25))
    }

    // MARK: Through the service

    @Test("The service records a pair, and reading it back from a fresh context gives the same pair")
    func servicePersistsThePair() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = try completedShift()
        context.insert(shift)
        try context.save()

        try ShiftService(context: context).setFuelAssumptions(
            milesPerGallon: try economy("28.5"),
            gasPricePerGallon: Money(minorUnits: 329),
            on: shift
        )

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<Shift>()).first)
        #expect(stored.fuelAssumptions.milesPerGallon == Decimal(string: "28.5"))
        #expect(stored.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 329))
    }

    @Test("The service refuses an invalid pair and writes nothing")
    func serviceRefusesAndWritesNothing() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = try completedShift()
        context.insert(shift)
        try ShiftService(context: context).setFuelAssumptions(
            milesPerGallon: try economy("25"),
            gasPricePerGallon: Money(minorUnits: 350),
            on: shift
        )

        #expect(throws: ShiftLifecycleError.invalidTransition(.invalidFuelEconomy)) {
            try ShiftService(context: context).setFuelAssumptions(
                milesPerGallon: .zero,
                gasPricePerGallon: Money(minorUnits: 499),
                on: shift
            )
        }

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<Shift>()).first)
        #expect(stored.fuelAssumptions.milesPerGallon == Decimal(25))
        #expect(stored.fuelAssumptions.gasPricePerGallon == Money(minorUnits: 350))
    }

    @Test("Removing through the service leaves the shift with no estimate")
    func serviceRemovesThePair() throws {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let shift = try completedShift()
        context.insert(shift)
        try ShiftService(context: context).setFuelAssumptions(
            milesPerGallon: try economy("25"),
            gasPricePerGallon: Money(minorUnits: 350),
            on: shift
        )

        try ShiftService(context: context).clearFuelAssumptions(on: shift)

        let fresh = ModelContext(container)
        let stored = try #require(try fresh.fetch(FetchDescriptor<Shift>()).first)
        #expect(stored.fuelAssumptions == .none)
    }

    // MARK: The route it is estimated over is the authoritative one

    @Test("Correcting the shift's end changes the recorded mileage, and the estimate follows it")
    func endCorrectionRederivesTheEstimate() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        // Three equal capture sessions of 3,600 m, so an estimate measured from
        // the positions that remain and one scaled by the time removed cannot be
        // confused for each other.
        for (index, startMinute) in [30.0, 180.0, 200.0].enumerated() {
            let session = UUID()
            for step in 0..<10 {
                context.insert(
                    RouteSample(
                        shift: shift,
                        sample: SyntheticRoute.sample(
                            at: start.addingTimeInterval(startMinute * 60 + Double(step) * 20),
                            northMetres: Double(index) * 9_000 + Double(step) * 400
                        ),
                        captureSessionID: session
                    )
                )
            }
        }
        try shift.end(at: start.addingTimeInterval(240 * 60))
        try shift.setFuelAssumptions(milesPerGallon: try economy("25"), gasPricePerGallon: Money(minorUnits: 350))
        try context.save()

        let before = try #require(shift.fuelEstimate(for: shift.recordedDistance()).consumption)
        #expect(SyntheticRoute.isCloseEnough(Self.metres(before.recordedMiles), to: 10_800))

        // Move the end back past the third session, which deletes its positions.
        try ShiftEndCorrectionService(context: context).correct(shift, to: start.addingTimeInterval(190 * 60))

        let after = try #require(shift.fuelEstimate(for: shift.recordedDistance()).consumption)
        #expect(
            SyntheticRoute.isCloseEnough(Self.metres(after.recordedMiles), to: 7_200),
            "The estimate is over the miles the remaining positions support"
        )
        #expect(after.gallons < before.gallons)
        #expect(after.cost < before.cost)
        #expect(
            after.milesPerGallon == before.milesPerGallon && after.gasPricePerGallon == before.gasPricePerGallon,
            "No assumption moved: the mileage did, and the estimate is derived rather than stored"
        )
        #expect(
            after.isRoutePartial,
            "A route that no longer reaches the shift's end is partial, so the estimate is a floor"
        )
    }

    // MARK: An estimate is not an expense

    @Test("Recording fuel assumptions creates no expense")
    func recordingCreatesNoExpense() throws {
        let context = try makeContext()
        let shift = try completedShift()
        context.insert(shift)

        try ShiftService(context: context).setFuelAssumptions(
            milesPerGallon: try economy("25"),
            gasPricePerGallon: Money(minorUnits: 350),
            on: shift
        )

        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty, "An estimate is arithmetic, not a cost recorded")
    }

    @Test("A recorded fuel expense is untouched by the estimate, and neither is derived from the other")
    func recordedFuelExpenseStaysItsOwnFact() throws {
        let context = try makeContext()
        let shift = try completedShift()
        context.insert(shift)

        let purchase = try Expense(
            occurredAt: start,
            amount: Money(minorUnits: 4_210),
            category: .fuel,
            noteText: ""
        )
        context.insert(purchase)

        try ShiftService(context: context).setFuelAssumptions(
            milesPerGallon: try economy("25"),
            gasPricePerGallon: Money(minorUnits: 350),
            on: shift
        )
        try context.save()

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1, "Nothing was created and nothing was removed")
        #expect(expenses.first?.amount == Money(minorUnits: 4_210), "And the recorded cost did not move")
        #expect(
            shift.fuelEstimate(for: route(miles: 50)).cost == Money(minorUnits: 700),
            "The estimate is derived from the mileage and the assumptions, never from a recorded expense"
        )
    }
}
