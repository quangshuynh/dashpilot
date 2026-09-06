import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Recorded expenses in the store: the v8 schema, the migration that adds them,
/// the service that writes them, and what survives a store being closed and
/// reopened.
///
/// Every amount, note and place name below is invented. The repository holds no
/// real driver history and names no real business.
@MainActor
@Suite("Expense persistence")
struct ExpensePersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotExpenseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The one place the migration plan's current shape is asserted.
    ///
    /// Deliberately a single authoritative check rather than a count repeated
    /// across suites: a schema version is added by one interval, and a figure
    /// scattered over unrelated files is one that gets updated in four places
    /// and forgotten in the fifth. It moves here from the delivery-earnings
    /// suite, which added the previous version.
    @Test("Version 8 is current, and it is the version that adds recorded expenses")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV8.versionIdentifier == Schema.Version(8, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 8)
        #expect(DashPilotMigrationPlan.stages.count == 7)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV8.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(entities == ["Shift", "RouteSample", "Delivery", "PickupPlace", "Expense"])

        let expense = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Expense" })
        let properties = Set(expense.properties.map(\.name))
        #expect(properties == ["id", "occurredAt", "amountValue", "categoryRawValue", "note"])
    }

    @Test("An expense has no relationship to a shift or a delivery")
    func expenseIsUnattached() throws {
        // The interval's substantive modelling decision, asserted as a shape: an
        // expense is dated rather than attached, so there is nowhere in the
        // store to put an attribution the driver never made.
        let expense = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Expense" })

        #expect(expense.relationships.isEmpty)
        #expect(!expense.properties.map(\.name).contains { $0.lowercased().contains("shift") })
        #expect(!expense.properties.map(\.name).contains { $0.lowercased().contains("delivery") })

        // And nothing was added to a shift either: v8 changes no existing entity.
        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        #expect(!shift.properties.map(\.name).contains { $0.lowercased().contains("expense") })
        #expect(!shift.relationships.map(\.name).contains { $0.lowercased().contains("expense") })
    }

    @Test("Version 7 described no expense at all")
    func versionSevenHeldNoExpenses() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV7.self)
        let entities = Set(schema.entities.map(\.name))

        #expect(entities == ["Shift", "RouteSample", "Delivery", "PickupPlace"])
        #expect(!entities.contains("Expense"), "The frozen v7 must describe the store as it was")

        // And the frozen copies still describe everything v7 did hold, so the
        // migration's starting point is the real one.
        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        #expect(delivery.properties.map(\.name).contains("grossEarningsAmount"))
        #expect(delivery.properties.map(\.name).contains("pickupPlace"))

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        #expect(shift.properties.map(\.name).contains("grossEarningsAmount"))

        let sample = try #require(schema.entities.first { $0.name == "RouteSample" })
        #expect(sample.properties.map(\.name).contains("captureSessionID"))
    }

    // MARK: Migration

    @Test("A version 7 store opens under version 8 with all of its history intact")
    func migratesFromVersionSeven() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidShiftID = UUID()
        let unpaidShiftID = UUID()
        let deliveryID = UUID()
        let cancelledID = UUID()
        let placeID = UUID()
        let captureSession = UUID()

        do {
            let v7 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV7.self, at: storeURL)
            let context = ModelContext(v7)

            let paid = DashPilotSchemaV7.Shift(
                id: paidShiftID,
                startedAt: start,
                endedAt: at(4 * 3600),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(paid)
            // A second shift with no amount, so the migration cannot quietly
            // turn "not recorded" into anything at all.
            context.insert(DashPilotSchemaV7.Shift(id: unpaidShiftID, startedAt: at(86_400)))

            for step in 0..<3 {
                context.insert(
                    DashPilotSchemaV7.RouteSample(
                        shift: paid,
                        timestamp: at(Double(step) * 60),
                        latitude: 40.0 + Double(step) * 0.001,
                        longitude: -75.0,
                        horizontalAccuracy: 8,
                        captureSessionID: captureSession
                    )
                )
            }

            let noodles = DashPilotSchemaV7.PickupPlace(
                id: placeID,
                displayName: "Nowhere Noodles",
                normalizedName: "nowhere noodles",
                createdAt: start
            )
            context.insert(noodles)

            context.insert(
                DashPilotSchemaV7.Delivery(
                    id: deliveryID,
                    shift: paid,
                    acceptedAt: at(600),
                    arrivedAtPickupAt: at(900),
                    pickedUpAt: at(1_500),
                    deliveredAt: at(2_400),
                    pickupPlace: noodles,
                    grossEarningsAmount: Decimal(string: "14.75")
                )
            )
            context.insert(
                DashPilotSchemaV7.Delivery(
                    id: cancelledID,
                    shift: paid,
                    acceptedAt: at(3_000),
                    arrivedAtPickupAt: at(3_180),
                    cancelledAt: at(3_600)
                )
            )

            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))

        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(shifts.count == 2)
        let paid = try #require(shifts.first { $0.id == paidShiftID })
        #expect(paid.startedAt == start)
        #expect(paid.endedAt == at(4 * 3600))
        #expect(paid.grossEarnings == Money(exact: "86.25"), "The exact decimal survives the migration")
        #expect(paid.routeSamples.count == 3)
        #expect(paid.routeSamples.allSatisfy { $0.captureSessionID == captureSession })
        #expect(paid.deliveries.count == 2)

        let unpaid = try #require(shifts.first { $0.id == unpaidShiftID })
        #expect(unpaid.grossEarnings == nil, "Not recorded stays not recorded, and never becomes $0.00")

        let delivered = try #require(paid.deliveries.first { $0.id == deliveryID })
        #expect(delivered.state == .delivered)
        #expect(delivered.pickedUpAt == at(1_500))
        #expect(delivered.pickupWait == 600)
        #expect(delivered.grossEarnings == Money(exact: "14.75"))
        #expect(delivered.pickupPlace?.id == placeID)
        #expect(delivered.pickupPlace?.displayName == "Nowhere Noodles")

        let cancelled = try #require(paid.deliveries.first { $0.id == cancelledID })
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.grossEarnings == nil)

        // And the whole point of the version: a table that exists and is empty.
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    @Test("Migrating invents no expense from mileage, earnings or anything else")
    func migrationFabricatesNothing() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let v7 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV7.self, at: storeURL)
            let context = ModelContext(v7)
            // A shift with an amount, a route and deliveries: everything a
            // plausible cost could have been derived from is present.
            let shift = DashPilotSchemaV7.Shift(
                startedAt: start,
                endedAt: at(6 * 3600),
                grossEarningsAmount: Decimal(string: "240.00")
            )
            context.insert(shift)
            for step in 0..<20 {
                context.insert(
                    DashPilotSchemaV7.RouteSample(
                        shift: shift,
                        timestamp: at(Double(step) * 30),
                        latitude: 40.0 + Double(step) * 0.004,
                        longitude: -75.0,
                        horizontalAccuracy: 8,
                        captureSessionID: UUID()
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))

        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        // The store still holds the work it held, so the emptiness above is the
        // absence of fabrication rather than the absence of a store.
        #expect(try context.fetchCount(FetchDescriptor<Shift>()) == 1)
    }

    @Test("A store written before expenses still migrates from the oldest version")
    func migratesFromVersionOne() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()

        do {
            let v1 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV1.self, at: storeURL)
            let context = ModelContext(v1)
            context.insert(DashPilotSchemaV1.Shift(id: shiftID, startedAt: start, endedAt: at(3_600)))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.completedDuration == 3_600)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    // MARK: Round trip

    @Test("A recorded expense is read back exactly as it was entered")
    func roundTrips() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        var expenseID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let expense = try ExpenseService(context: context).record(
                amount: try money("42.10"),
                category: .fuel,
                occurredAt: start,
                noteText: "Half tank before the lunch rush"
            )
            expenseID = expense.id
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Expense>()).first)

        #expect(stored.id == expenseID)
        #expect(stored.amount == Money(exact: "42.10"))
        #expect(stored.amount.amount == Decimal(string: "42.10"), "A decimal attribute, not a double")
        #expect(stored.category == .fuel)
        #expect(stored.occurredAt == start)
        #expect(stored.note == "Half tank before the lunch rush")
    }

    @Test("Deleting a shift leaves the expenses alone")
    func deletingAShiftKeepsExpenses() throws {
        let context = try makeContext()
        let shifts = ShiftService(context: context)
        let shift = try shifts.startShift(at: start)
        try shifts.endActiveShift(at: at(3_600))
        try ExpenseService(context: context).record(
            amount: try money("42.10"),
            category: .fuel,
            occurredAt: at(1_800)
        )

        try shifts.deleteCompletedShift(shift)

        // Nothing cascades, because nothing relates them: the cost happened
        // whether or not the shift's record is still there.
        #expect(try context.fetchCount(FetchDescriptor<Shift>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
    }

    // MARK: The service

    @Test("The service records, edits and deletes, and nothing else changes")
    func serviceWrites() throws {
        let context = try makeContext()
        let service = ExpenseService(context: context)

        let expense = try service.record(
            amount: try money("6.50"),
            category: .parkingAndTolls,
            occurredAt: start,
            noteText: "Garage on the corner"
        )
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)

        try service.update(
            expense,
            amount: try money("7.00"),
            category: .parkingAndTolls,
            occurredAt: at(600),
            noteText: ""
        )
        let updated = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(updated.amount == Money(exact: "7.00"))
        #expect(updated.occurredAt == at(600))
        #expect(updated.note == nil)

        try service.delete(expense)
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    @Test("The service refuses a negative amount and writes nothing")
    func serviceRefusesNegative() throws {
        let context = try makeContext()

        #expect(throws: ExpenseRecordingError.invalidExpense(.negativeAmount)) {
            try ExpenseService(context: context).record(
                amount: Money(minorUnits: -100),
                category: .fuel,
                occurredAt: start
            )
        }

        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
    }

    @Test("The service refuses to change an expense the store no longer holds")
    func serviceRefusesADeletedRow() throws {
        let context = try makeContext()
        let service = ExpenseService(context: context)
        let expense = try service.record(amount: try money("1.00"), category: .other, occurredAt: start)

        try service.delete(expense)

        #expect(throws: ExpenseRecordingError.expenseNoLongerExists) {
            try service.update(
                expense,
                amount: try money("2.00"),
                category: .other,
                occurredAt: start,
                noteText: ""
            )
        }
        #expect(try context.fetch(FetchDescriptor<Expense>()).isEmpty, "And nothing is resurrected")
    }

    @Test("An expense can be recorded on a day with no shift at all")
    func expenseWithoutAShift() throws {
        let context = try makeContext()

        try ExpenseService(context: context).record(
            amount: try money("89.99"),
            category: .maintenance,
            occurredAt: start,
            noteText: "Oil change"
        )

        #expect(try context.fetchCount(FetchDescriptor<Shift>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
    }

    @Test("Reading a period reads by the expense's own date, newest first")
    func readsAPeriod() throws {
        let context = try makeContext()
        let service = ExpenseService(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let day = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        try service.record(amount: try money("1.00"), category: .fuel, occurredAt: day.start)
        try service.record(amount: try money("2.00"), category: .fuel, occurredAt: day.start.addingTimeInterval(3_600))
        // The first instant of the next day: outside a half-open span.
        try service.record(amount: try money("3.00"), category: .fuel, occurredAt: day.end)

        let inDay = try service.expenses(in: day)

        #expect(inDay.count == 2)
        #expect(inDay.map(\.amount) == [Money(exact: "2.00"), Money(exact: "1.00")], "Newest first")
        #expect(try service.allExpenses().count == 3)
    }
}
