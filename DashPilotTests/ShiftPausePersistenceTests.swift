import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Shift pauses in the store: the v9 schema, the migration that adds them, what
/// the model derives from them, and what survives a store being closed and
/// reopened.
///
/// Every timestamp and amount below is invented. The repository holds no real
/// driver history.
@MainActor
@Suite("Shift pause persistence")
struct ShiftPausePersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.makeInMemoryContainer())
    }

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotPauseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// v9's own identifier and the entity it added.
    ///
    /// The migration plan's *current* shape is asserted once, in the suite for
    /// whichever version is current, which is now
    /// `RouteSampleRelationshipTests`. A count repeated across suites is one
    /// that gets updated in four places and forgotten in the fifth, so this
    /// keeps only what is true about v9 and nothing about how many versions
    /// there are.
    @Test("Version 9 is the version that adds shift pauses")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV9.versionIdentifier == Schema.Version(9, 0, 0))

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ]
        )

        let pause = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "ShiftPause" })
        #expect(Set(pause.properties.map(\.name)) == ["id", "startedAt", "endedAt", "shift"])
    }

    /// The modelling decision, asserted as a shape: pausing does not touch the
    /// shift's own attributes, so `endedAt == nil` still means unfinished and
    /// nothing had to be taught a second definition.
    @Test("The shift gained a relationship and not a paused flag")
    func shiftGainedNoFlag() throws {
        let shift = try #require(ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" })
        let attributes = Set(shift.attributes.map(\.name))

        #expect(
            attributes == [
                "id", "startedAt", "endedAt", "grossEarningsAmount",
                "fuelMilesPerGallonValue", "fuelGasPricePerGallonAmount", "fuelVehicleName"
            ]
        )
        #expect(shift.relationships.map(\.name).contains("pauses"))
        #expect(!attributes.contains { $0.lowercased().contains("paus") })
        #expect(!attributes.contains { $0.lowercased().contains("active") })
    }

    // MARK: Migration

    /// The substantive migration claim: a v8 store holds no evidence that any
    /// shift was ever paused, so every shift arrives with no pauses, zero paused
    /// time, and a working duration identical to the elapsed one it has always
    /// had. Nothing is inferred from a long shift or a gap in a route.
    @Test("A version 8 store opens under version 9 with every shift's duration unchanged")
    func migratesFromVersionEight() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let paidShiftID = UUID()
        let longShiftID = UUID()
        let captureSession = UUID()

        do {
            let v8 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV8.self, at: storeURL)
            let context = ModelContext(v8)

            let paid = DashPilotSchemaV8.Shift(
                id: paidShiftID,
                startedAt: start,
                endedAt: at(4 * 3600),
                grossEarningsAmount: Decimal(string: "86.25")
            )
            context.insert(paid)

            // A long shift with one delivery early on and a route that stops
            // after it: the shape that most resembles a break, and the one the
            // migration must not read as one.
            let long = DashPilotSchemaV8.Shift(id: longShiftID, startedAt: at(86_400), endedAt: at(86_400 + 10 * 3600))
            context.insert(long)

            for step in 0..<3 {
                context.insert(
                    DashPilotSchemaV8.RouteSample(
                        shift: long,
                        timestamp: at(86_400 + Double(step) * 60),
                        latitude: 40.0 + Double(step) * 0.001,
                        longitude: -75.0,
                        horizontalAccuracy: 8,
                        captureSessionID: captureSession
                    )
                )
            }

            context.insert(
                DashPilotSchemaV8.Delivery(
                    id: UUID(),
                    shift: long,
                    acceptedAt: at(86_400 + 600),
                    deliveredAt: at(86_400 + 2_400)
                )
            )

            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))

        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(shifts.count == 2, "Migration must not drop shifts")

        let paid = try #require(shifts.first)
        #expect(paid.id == paidShiftID)
        #expect(paid.pauses.isEmpty)
        #expect(paid.lifecycleState == .ended)
        #expect(paid.completedDuration == 4 * 3600.0)
        #expect(paid.completedWorkingDuration == 4 * 3600.0, "A shift that could not be paused was paused for no time")
        // Spelled out: `.none` against an optional would resolve to `nil`,
        // which is a different claim from "measured, and it was zero".
        #expect(paid.completedPausedTime == ShiftPausedTime.none)
        #expect(paid.completedPausedTime?.duration == 0)
        #expect(paid.grossEarnings?.amount == Decimal(string: "86.25"))

        let long = try #require(shifts.last)
        #expect(long.id == longShiftID)
        #expect(long.pauses.isEmpty, "A gap in a route is not evidence of a break")
        #expect(long.completedWorkingDuration == 10 * 3600.0)
        #expect(long.routeSamples().count == 3)
        #expect(long.deliveries.count == 1)

        // The pause table exists and is empty, which is the only honest state
        // for it.
        #expect(try context.fetch(FetchDescriptor<ShiftPause>()).isEmpty)
    }

    @Test("A version 1 store reaches version 9 with its shifts and their durations intact")
    func migratesFromVersionOne() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()
        do {
            let v1 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV1.self, at: storeURL)
            let context = ModelContext(v1)
            context.insert(DashPilotSchemaV1.Shift(id: shiftID, startedAt: start, endedAt: at(7_200)))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(stored.id == shiftID)
        #expect(stored.completedDuration == 7_200)
        #expect(stored.completedWorkingDuration == 7_200)
        #expect(stored.pauses.isEmpty)
    }

    // MARK: What the model derives

    @Test("A shift with an open pause is paused, and still unfinished")
    func openPauseMakesItPaused() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        #expect(shift.lifecycleState == .running)

        let pause = try shift.beginPause(at: at(1_800))
        context.insert(pause)
        try context.save()

        #expect(shift.lifecycleState == .paused)
        #expect(shift.isPaused)
        #expect(shift.isActive, "endedAt is untouched, so the shift is still the unfinished one")
        #expect(shift.endedAt == nil)
        #expect(shift.openPause?.startedAt == at(1_800))
    }

    @Test("Closing the pause returns the shift to running")
    func closingThePauseResumes() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        context.insert(try shift.beginPause(at: at(1_800)))
        try context.save()

        try shift.endOpenPause(at: at(3_600))
        try context.save()

        #expect(shift.lifecycleState == .running)
        #expect(shift.openPause == nil)
        #expect(shift.pauses.count == 1)
        #expect(shift.pausedTime(asOf: at(7_200)).duration == 1_800)
        #expect(shift.workingDuration(asOf: at(7_200)) == 5_400)
    }

    @Test("The model refuses a second open pause and a resume with nothing to resume")
    func modelRefusesImpossibleTransitions() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        #expect(throws: ShiftError.notPaused) { try shift.endOpenPause(at: at(600)) }

        context.insert(try shift.beginPause(at: at(600)))
        try context.save()

        #expect(throws: ShiftError.alreadyPaused) { try shift.beginPause(at: at(900)) }

        try shift.endOpenPause(at: at(1_200))
        try context.save()

        try shift.end(at: at(3_600))
        #expect(throws: ShiftError.shiftAlreadyEnded) { try shift.beginPause(at: at(3_700)) }
        #expect(throws: ShiftError.shiftAlreadyEnded) { try shift.endOpenPause(at: at(3_700)) }
    }

    @Test("An ended shift reads as ended even if the store holds an open pause on it")
    func endedOutranksPaused() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        context.insert(try shift.beginPause(at: at(600)))
        try shift.end(at: at(3_600))
        try context.save()

        #expect(shift.lifecycleState == .ended)
        #expect(!shift.isPaused)
        // The pause is still clipped to the shift, so the anomalous row cannot
        // subtract time the shift never covered.
        #expect(shift.completedPausedTime?.duration == 3_000)
        #expect(shift.completedWorkingDuration == 600)
    }

    // MARK: Reopening

    @Test("A paused shift is still paused after the store is closed and reopened")
    func pausedShiftSurvivesReopening() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()
        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(id: shiftID, startedAt: start)
            context.insert(shift)
            context.insert(try shift.beginPause(at: at(1_800)))
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(stored.id == shiftID)
        #expect(stored.lifecycleState == .paused)
        #expect(stored.openPause?.startedAt == at(1_800))
        // The fetch that recovers an unfinished shift is unchanged, which is the
        // whole reason `endedAt` was left alone.
        let unfinished = try context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.endedAt == nil }))
        #expect(unfinished.count == 1)
    }

    @Test("Deleting a shift takes its pauses with it")
    func deletingAShiftCascadesToPauses() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)
        context.insert(try shift.beginPause(at: at(600)))
        try shift.endOpenPause(at: at(1_200))
        context.insert(try shift.beginPause(at: at(2_400)))
        try shift.endOpenPause(at: at(3_000))
        try shift.end(at: at(3_600))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ShiftPause>()).count == 2)

        context.delete(shift)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ShiftPause>()).isEmpty, "No pause may outlive its shift")
    }

    @Test("Several pauses on one shift are ordered and totalled")
    func severalPauses() throws {
        let context = try makeContext()
        let shift = Shift(startedAt: start)
        context.insert(shift)

        context.insert(try shift.beginPause(at: at(3_600)))
        try shift.endOpenPause(at: at(5_400))
        context.insert(try shift.beginPause(at: at(9_000)))
        try shift.endOpenPause(at: at(10_800))
        try shift.end(at: at(14_400))
        try context.save()

        #expect(shift.pausesInOrder.map(\.startedAt) == [at(3_600), at(9_000)])
        #expect(shift.completedPausedTime?.duration == 3_600)
        #expect(shift.completedPausedTime?.intervalCount == 2)
        #expect(shift.completedDuration == 14_400)
        #expect(shift.completedWorkingDuration == 10_800)
    }
}
