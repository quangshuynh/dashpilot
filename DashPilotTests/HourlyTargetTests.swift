import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Comparing a shift's gross earnings per working hour with a personal target:
/// one rate, the existing one; neutral words; a band that rounding cannot flip;
/// and missing never read as zero.
@Suite("Hourly target comparison")
struct HourlyTargetComparisonTests {
    private func money(_ text: String) -> Money { Money(amount: Decimal(string: text)!) }

    @Test("Above, near and below a $25.00 target, with the 2% band inclusive at both edges")
    func standings() throws {
        let target = money("25.00")
        let cases: [(String, HourlyTargetComparison.Standing)] = [
            ("27.42", .above), ("25.51", .above), ("25.50", .near), ("25.00", .near),
            ("24.50", .near), ("24.49", .below), ("21.80", .below), ("0.00", .below)
        ]
        for (rate, standing) in cases {
            let comparison = try #require(HourlyTargetComparison(rate: money(rate), target: target))
            #expect(comparison.standing == standing, "\(rate) against 25.00")
        }
    }

    @Test("The rate is compared at the cent it is shown at, so $24.996 is not below a $25.00 target")
    func comparedAsShown() throws {
        // A four-place rate as ShiftMetricsCalculator produces it.
        let comparison = try #require(HourlyTargetComparison(rate: money("24.9960"), target: money("25.00")))
        #expect(comparison.rate == money("25.00"))
        #expect(comparison.standing == .near)
        #expect(comparison.difference == .zero)
    }

    @Test("Missing rate or missing target is no comparison, and a target of zero is not one")
    func missingIsNotZero() {
        #expect(HourlyTargetComparison(rate: nil, target: money("25.00")) == nil)
        #expect(HourlyTargetComparison(rate: money("20.00"), target: nil) == nil)
        #expect(HourlyTargetComparison(rate: money("20.00"), target: .zero) == nil)
        #expect(HourlyTargetComparison(rate: money("20.00"), target: money("-5.00")) == nil)
    }

    @Test("The statements: an amount above, a percentage below, the band in words")
    func statements() throws {
        let locale = Locale(identifier: "en_US")
        let above = try #require(HourlyTargetComparison(rate: money("27.42"), target: money("25.00")))
        #expect(above.statement(locale: locale) == "$2.42/hr above your $25.00 target")
        let below = try #require(HourlyTargetComparison(rate: money("21.80"), target: money("25.00")))
        #expect(below.statement(locale: locale) == "87% of your $25.00 target")
        let near = try #require(HourlyTargetComparison(rate: money("25.10"), target: money("25.00")))
        #expect(near.statement(locale: locale) == "Within 2% of your $25.00 target")
        #expect(below.spokenStatement(locale: locale).hasPrefix("Below target. 87 percent"))
    }

    @Test("No judgement in any wording")
    func neutralWording() throws {
        let locale = Locale(identifier: "en_US")
        var words: [String] = HourlyTargetComparison.Standing.allCases.map(\.title)
        for rate in ["30.00", "25.00", "10.00"] {
            let comparison = try #require(HourlyTargetComparison(rate: money(rate), target: money("25.00")))
            words += [comparison.statement(locale: locale), comparison.spokenStatement(locale: locale)]
        }
        words += [PeriodHourlyTargetSummary(withTarget: 3, compared: 2, atOrAbove: 1).statement ?? ""]
        for text in words {
            for judgement in ["bad", "poor", "fail", "excellent", "great", "should", "missed"] {
                #expect(!text.lowercased().contains(judgement), "\(text)")
            }
        }
    }

    @Test("A period counts each shift against its own target, apart from shifts with no target or no rate")
    func periodCount() {
        let summary = PeriodHourlyTargetSummary(pairs: [
            (money("30.00"), money("25.00")),   // above
            (money("24.80"), money("25.00")),   // near
            (money("20.00"), money("30.00")),   // below its own, higher target
            (nil, money("25.00")),              // a target, no rate
            (money("40.00"), nil)               // no target: not counted at all
        ])
        #expect(summary == PeriodHourlyTargetSummary(withTarget: 4, compared: 3, atOrAbove: 2))
        #expect(summary.statement == "At or near target on 2 of 3 shifts · 1 without a rate")
        #expect(PeriodHourlyTargetSummary(pairs: [(money("40.00"), nil)]).statement == nil, "Silent with no targets")
        #expect(PeriodHourlyTargetSummary(withTarget: 1, compared: 0, atOrAbove: 0).statement
            == "1 shift had a target but no rate to compare")
    }
}

/// Where the target lives and how it moves: a default in Settings, a snapshot
/// on each shift taken when it starts, and never reapplied.
@MainActor
@Suite("Hourly target snapshot")
struct HourlyTargetSnapshotTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private func at(_ hours: Double) -> Date { start.addingTimeInterval(hours * 3_600) }
    private func money(_ text: String) -> Money { Money(amount: Decimal(string: text)!) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// Starts a shift at `hour`, ends it two working hours later and records
    /// `earnings`.
    private func workedShift(at hour: Double, earnings: String?, in context: ModelContext) throws -> Shift {
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: at(hour))
        try shifts.endActiveShift(at: at(hour + 2))
        if let earnings { try shift.setGrossEarnings(money(earnings)) }
        try context.save()
        return shift
    }

    @Test("A shift records the target set when it started, and a later change reclassifies nothing")
    func historicallyStable() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)

        try settings.setHourlyTarget(money("25.00"))
        let first = try workedShift(at: 0, earnings: "55.00", in: context)   // $27.50/hr
        try settings.setHourlyTarget(money("30.00"))
        let second = try workedShift(at: 10, earnings: "55.00", in: context)  // $27.50/hr

        #expect(first.hourlyTarget == money("25.00"))
        #expect(second.hourlyTarget == money("30.00"))
        #expect(first.hourlyTargetComparison(for: .none)?.standing == .above, "Against its own $25.00")
        #expect(second.hourlyTargetComparison(for: .none)?.standing == .below, "Against its own $30.00")

        try settings.setHourlyTarget(nil)
        #expect(first.hourlyTarget == money("25.00"), "Removing the default removes nothing recorded")
        let fresh = try ModelContext(context.container).fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(fresh.map(\.hourlyTarget) == [money("25.00"), money("30.00")])
    }

    @Test("A shift started with no target set records none, and is compared with nothing")
    func noTargetIsNotZero() throws {
        let context = try makeContext()
        let shift = try workedShift(at: 0, earnings: "40.00", in: context)
        #expect(shift.hourlyTarget == nil)
        #expect(shift.hourlyTargetComparison(for: .none) == nil)
    }

    @Test("Setting a target while a shift runs changes the next shift, not that one")
    func setMidShift() throws {
        let context = try makeContext()
        let running = try ShiftService(context: context).startShift(at: at(0))
        try SettingsService(context: context).setHourlyTarget(money("25.00"))
        #expect(running.hourlyTarget == nil)
    }

    @Test("A shift's target is written once, on a running shift, and only as a positive amount")
    func oneWriter() throws {
        let context = try makeContext()
        let shift = try ShiftService(context: context).startShift(at: at(0))
        #expect(throws: ShiftError.nonPositiveHourlyTarget) { try shift.recordStartingHourlyTarget(.zero) }
        try shift.recordStartingHourlyTarget(money("25.00"))
        #expect(throws: ShiftError.hourlyTargetAlreadyRecorded) { try shift.recordStartingHourlyTarget(money("30.00")) }
        try ShiftService(context: context).endActiveShift(at: at(1))
        #expect(throws: ShiftError.shiftAlreadyEnded) { try shift.recordStartingHourlyTarget(money("30.00")) }
    }

    @Test("Settings refuse a target of zero or less and keep the previous one")
    func settingsRefuseZero() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.setHourlyTarget(money("25.00"))
        #expect(throws: SettingsError.invalidSettings(.nonPositiveHourlyTarget)) { try settings.setHourlyTarget(.zero) }
        #expect(settings.hourlyTarget() == money("25.00"))
        #expect(MoneyInputError.negative.message(for: .hourlyTarget) == "A target cannot be a negative amount.")
    }

    @Test("A week's summary counts each shift against the target it started with")
    func weekCounts() throws {
        let context = try makeContext()
        let settings = SettingsService(context: context)
        try settings.setHourlyTarget(money("25.00"))
        _ = try workedShift(at: 0, earnings: "60.00", in: context)    // 30.00: above
        _ = try workedShift(at: 5, earnings: "40.00", in: context)    // 20.00: below
        _ = try workedShift(at: 10, earnings: nil, in: context)       // no rate
        try settings.setHourlyTarget(nil)
        _ = try workedShift(at: 15, earnings: "80.00", in: context)   // no target

        let shifts = try context.fetch(FetchDescriptor<Shift>())
        let period = try #require(ReportingPeriod(from: at(-24), through: at(48)))
        let metrics = PeriodMetricsCalculator().metrics(of: shifts.map { $0.periodRecord(for: .none) }, in: period)
        #expect(metrics.hourlyTarget == PeriodHourlyTargetSummary(withTarget: 3, compared: 2, atOrAbove: 1))
    }

    @Test("Export carries the shift's own target, null when it had none, without a version bump")
    func exported() throws {
        let fixture = try ExportFixture()
        try SettingsService(context: fixture.context).setHourlyTarget(money("25.00"))
        let shift = try fixture.completedShift(earnings: "100.00")
        let record = try fixture.exportRecord(of: shift)
        #expect(record.targetGrossPerWorkingHour == ExportAmount.recorded(shift.hourlyTarget))

        let document = ExportDocument(scope: .shift(shift.id), shifts: [record], summary: nil, exportedAt: ExportFixture.start)
        let json = try #require(String(data: try ExportDocumentEncoder().json(for: document), encoding: .utf8))
        #expect(json.contains("\"targetGrossPerWorkingHour\""))
        #expect(ExportFormat.version == 6, "Additive JSON field, by the contract's own rule")
    }
}

/// Schema v22: two optional columns, a lightweight stage, and nothing invented
/// for a shift that never had a target.
@MainActor
@Suite("Hourly target persistence")
struct HourlyTargetPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotHourlyTargetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory.appending(path: "DashPilot.store"), { try? FileManager.default.removeItem(at: directory) })
    }

    /// The plan's own shape, asserted here because v22 is the current version.
    @Test("Version 22 is the current version, and it adds no entity")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV22.versionIdentifier == Schema.Version(22, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 22)
        #expect(DashPilotMigrationPlan.stages.count == 21)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV22.Type)
        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ]
        )
    }

    @Test("Frozen v21 has no target column; v22 has it on the shift and the settings row only")
    func theColumns() throws {
        let frozen = Schema(versionedSchema: DashPilotSchemaV21.self)
        for entity in frozen.entities {
            #expect(!entity.properties.map(\.name).contains("targetGrossPerWorkingHourAmount"))
        }
        let frozenSettings = try #require(frozen.entities.first { $0.name == "DriverSettings" })
        #expect(frozenSettings.properties.map(\.name).contains("resumesDrivingAfterDeliveryProgress"), "v21's own column")

        for entity in ModelContainerFactory.currentSchema.entities {
            let has = entity.properties.map(\.name).contains("targetGrossPerWorkingHourAmount")
            #expect(has == ["Shift", "DriverSettings"].contains(entity.name), "\(entity.name)")
        }
    }

    @Test("A version 21 store migrates with no target anywhere and nothing recorded moved")
    func migratesFromTwentyOne() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()

        do {
            let v21 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV21.self, at: storeURL)
            let context = ModelContext(v21)
            context.insert(
                DashPilotSchemaV21.DriverSettings(
                    id: DriverSettings.singletonID,
                    gasPricePerGallonAmount: Decimal(string: "3.29"),
                    resumesDrivingAfterDeliveryProgress: true
                )
            )
            context.insert(
                DashPilotSchemaV21.Shift(
                    id: shiftID,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(7_200),
                    grossEarningsAmount: Decimal(string: "55.00"),
                    fuelMilesPerGallonValue: 34
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.id == shiftID)
        #expect(shift.hourlyTarget == nil, "No target invented, and not $0.00")
        #expect(shift.hourlyTargetComparison(for: .none) == nil)
        #expect(shift.grossEarnings == Money(amount: Decimal(string: "55.00")!))
        #expect(shift.endedAt == start.addingTimeInterval(7_200))

        let settings = try #require(try context.fetch(FetchDescriptor<DriverSettings>()).first)
        #expect(settings.hourlyTarget == nil)
        #expect(settings.resumesDrivingAfterDeliveryProgress)
        #expect(settings.gasPricePerGallon == Money(amount: Decimal(string: "3.29")!))
    }

    @Test("A version 20 store reaches version 22 through both stages")
    func migratesFromTwenty() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        do {
            let v20 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV20.self, at: storeURL)
            let context = ModelContext(v20)
            context.insert(DashPilotSchemaV20.Shift(startedAt: start))
            try context.save()
        }
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        #expect(shift.hourlyTarget == nil)
        #expect(try context.fetch(FetchDescriptor<DriverSettings>()).isEmpty)
    }

    @Test("The default and a shift's snapshot survive closing and reopening the store")
    func roundTrip() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            try SettingsService(context: context).setHourlyTarget(Money(minorUnits: 2_500))
            _ = try ShiftService(context: context).startShift(at: start)
        }
        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(SettingsService(context: context).hourlyTarget() == Money(minorUnits: 2_500))
        #expect(try context.fetch(FetchDescriptor<Shift>()).first?.hourlyTarget == Money(minorUnits: 2_500))
    }
}
