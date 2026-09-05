import Foundation
import SwiftData
import Testing
@testable import DashPilot

@MainActor
@Suite("Shift earnings persistence")
struct ShiftEarningsPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// A store location that is deleted when the test finishes.
    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotEarningsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    @Test("Version 4 is current, and adds earnings to the shift")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 4)
        #expect(DashPilotMigrationPlan.stages.count == 3)

        let shift = try #require(
            ModelContainerFactory.currentSchema.entities.first { $0.name == "Shift" }
        )
        #expect(shift.properties.map(\.name).contains("grossEarningsAmount"))
    }

    @Test("Version 3 shifts recorded no earnings")
    func versionThreeHeldNoEarnings() throws {
        let shift = try #require(
            Schema(versionedSchema: DashPilotSchemaV3.self).entities.first { $0.name == "Shift" }
        )
        let properties = shift.properties.map(\.name)

        #expect(properties.contains("startedAt"))
        #expect(
            !properties.contains("grossEarningsAmount"),
            "The frozen v3 model must describe the store as it was, not as it is now"
        )
    }

    // MARK: Round trip

    @Test("A recorded amount survives closing and reopening the store")
    func earningsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(id: shiftID, startedAt: start)
            try shift.end(at: start.addingTimeInterval(3600))
            context.insert(shift)
            try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "86.25")), on: shift)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let reopened = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(reopened.id == shiftID)
        #expect(reopened.grossEarnings == Money(exact: "86.25"))
        // Exactness is the whole reason the amount is not a `Double`: 86.25 is
        // representable in binary, so the assertion that matters is one that
        // is not.
        #expect(reopened.grossEarnings?.amount == Decimal(string: "86.25"))
    }

    @Test("An awkward decimal comes back out of the store unchanged")
    func exactDecimalsSurviveAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(startedAt: start)
            try shift.end(at: start.addingTimeInterval(3600))
            context.insert(shift)
            try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "0.10")), on: shift)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let stored = try #require(try context.fetch(FetchDescriptor<Shift>()).first?.grossEarnings)

        #expect(stored + (try #require(Money(exact: "0.20"))) == Money(exact: "0.30"))
    }

    @Test("Zero and no amount stay different states across a reopen")
    func zeroAndMissingStayDistinct() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let paidNothingID = UUID()
        let notRecordedID = UUID()

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let paidNothing = Shift(id: paidNothingID, startedAt: start)
            try paidNothing.end(at: start.addingTimeInterval(3600))
            let notRecorded = Shift(id: notRecordedID, startedAt: start.addingTimeInterval(7200))
            try notRecorded.end(at: start.addingTimeInterval(10_800))
            context.insert(paidNothing)
            context.insert(notRecorded)
            try ShiftService(context: context).setGrossEarnings(.zero, on: paidNothing)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))

        #expect(shifts.first?.id == paidNothingID)
        #expect(shifts.first?.grossEarnings == Money.zero, "A shift that paid nothing recorded that it paid nothing")
        #expect(shifts.last?.id == notRecordedID)
        #expect(shifts.last?.grossEarnings == nil, "A shift with no amount entered has no amount")
    }

    @Test("A removed amount stays removed across a reopen")
    func removalSurvivesAReopen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shift = Shift(startedAt: start)
            try shift.end(at: start.addingTimeInterval(3600))
            context.insert(shift)
            let service = ShiftService(context: context)
            try service.setGrossEarnings(try #require(Money(exact: "86.25")), on: shift)
            try service.clearGrossEarnings(on: shift)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(try context.fetch(FetchDescriptor<Shift>()).first?.grossEarnings == nil)
    }

    // MARK: Migration

    @Test("A version 3 store opens under version 4 with its shifts, route and no invented earnings")
    func migratesAVersionThreeStore() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let completedID = UUID()
        let runningID = UUID()
        let session = UUID()

        // A store exactly as a build without earnings entry would have left it.
        do {
            let v3 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV3.self, at: storeURL)
            let context = ModelContext(v3)
            let completed = DashPilotSchemaV3.Shift(
                id: completedID,
                startedAt: start,
                endedAt: start.addingTimeInterval(3600)
            )
            context.insert(completed)
            context.insert(DashPilotSchemaV3.Shift(id: runningID, startedAt: start.addingTimeInterval(7200)))
            for step in 0..<4 {
                let position = SyntheticRoute.sample(
                    at: start.addingTimeInterval(TimeInterval(step) * 10),
                    northMetres: Double(step) * 100
                )
                context.insert(
                    DashPilotSchemaV3.RouteSample(
                        shift: completed,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shifts = try context.fetch(FetchDescriptor<Shift>(sortBy: [SortDescriptor(\.startedAt)]))
        let samples = try context.fetch(FetchDescriptor<RouteSample>(sortBy: [SortDescriptor(\.timestamp)]))

        #expect(shifts.count == 2, "Migration must not drop shifts")
        #expect(shifts.map(\.id) == [completedID, runningID])
        #expect(shifts.first?.endedAt == start.addingTimeInterval(3600))
        #expect(shifts.last?.endedAt == nil, "The shift that was still running is still running")
        #expect(
            shifts.allSatisfy { $0.grossEarnings == nil },
            "A shift recorded before earnings entry existed has no amount, not an amount of zero"
        )
        #expect(samples.count == 4, "Migration must not drop stored positions")
        #expect(samples.allSatisfy { $0.captureSessionID == session }, "Capture continuity survives")
        #expect(samples.allSatisfy { $0.shift?.id == completedID })
    }

    @Test("A migrated shift still measures its route and can then record earnings")
    func aMigratedShiftStillWorks() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let session = UUID()

        do {
            let v3 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV3.self, at: storeURL)
            let context = ModelContext(v3)
            let shift = DashPilotSchemaV3.Shift(startedAt: start, endedAt: start.addingTimeInterval(60))
            context.insert(shift)
            for step in 0..<4 {
                let position = SyntheticRoute.sample(
                    at: start.addingTimeInterval(TimeInterval(step) * 10),
                    northMetres: Double(step) * 100
                )
                context.insert(
                    DashPilotSchemaV3.RouteSample(
                        shift: shift,
                        timestamp: position.timestamp,
                        latitude: position.latitude,
                        longitude: position.longitude,
                        horizontalAccuracy: position.horizontalAccuracy,
                        captureSessionID: session
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let distance = shift.recordedDistance()

        #expect(distance.isMeasured)
        #expect(SyntheticRoute.isCloseEnough(distance.metres, to: 300), "measured \(distance.metres) m")
        #expect(!distance.usesInferredContinuity, "A v3 route already recorded its continuity")

        try ShiftService(context: context).setGrossEarnings(try #require(Money(exact: "42.00")), on: shift)

        #expect(shift.grossEarnings == Money(exact: "42.00"))
    }

    @Test("A version 1 store migrates all the way to version 4 without earnings")
    func migratesAVersionOneStoreToVersionFour() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }
        let shiftID = UUID()

        do {
            let v1 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV1.self, at: storeURL)
            let context = ModelContext(v1)
            context.insert(
                DashPilotSchemaV1.Shift(id: shiftID, startedAt: start, endedAt: start.addingTimeInterval(3600))
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.completedDuration == 3600)
        #expect(shift.routeSamples.isEmpty)
        #expect(shift.grossEarnings == nil)
    }
}
