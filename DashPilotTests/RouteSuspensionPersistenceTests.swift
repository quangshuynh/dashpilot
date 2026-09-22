import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Schema v16: the one new entity, and the migration that writes nothing into
/// it.
///
/// **The migration's whole claim is an absence.** A v15 store holds every route
/// sample it retained and no record of *why* any stretch of route is missing:
/// capture stops for a pause, a lost permission, a terminated process and a
/// backgrounded start, and the gaps they leave are identical. Reading a
/// suspension out of a gap would put a statement the driver never made into
/// their history, so a migrated store opens with none.
@MainActor
@Suite("Route suspension persistence")
struct RouteSuspensionPersistenceTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStoreURL() throws -> (url: URL, cleanUp: () -> Void) {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotSuspensionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appending(path: "DashPilot.store"),
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    // MARK: Schema

    /// The plan's own shape, asserted here because v16 is the current version.
    ///
    /// The repository's convention is that the count of versions and stages
    /// lives in the suite belonging to whichever version is current, so it is
    /// updated in one place rather than in several. It moved here from
    /// `VehicleSettingsPersistenceTests`, which owned it while v15 was current.
    @Test("Version 16 is the current version, and it is the one that adds the suspension")
    func schemaVersion() throws {
        #expect(DashPilotSchemaV16.versionIdentifier == Schema.Version(16, 0, 0))
        #expect(DashPilotMigrationPlan.schemas.count == 16)
        #expect(DashPilotMigrationPlan.stages.count == 15)
        #expect(DashPilotMigrationPlan.schemas.last is DashPilotSchemaV16.Type)

        let entities = Set(ModelContainerFactory.currentSchema.entities.map(\.name))
        #expect(
            entities == [
                "Shift", "RouteSample", "RouteSuspension", "Delivery", "PickupPlace", "Expense",
                "ShiftPause", "Offer", "DeliveryTip", "VehicleProfile", "DriverSettings"
            ],
            "v16 adds exactly one entity and drops none"
        )
    }

    /// The claim the whole design rests on, read straight off the schema: a
    /// suspension belongs to the shift and to nothing else.
    @Test("A suspension joins the shift, and no delivery in either direction")
    func aSuspensionBelongsToTheShift() throws {
        let schema = ModelContainerFactory.currentSchema

        let suspension = try #require(schema.entities.first { $0.name == "RouteSuspension" })
        #expect(Set(suspension.properties.map(\.name)) == ["id", "startedAt", "endedAt", "shift"])
        #expect(
            suspension.relationships.map(\.destination) == ["Shift"],
            "One vehicle, one shift. A driver shopping for one order while carrying another is parked once"
        )

        let delivery = try #require(schema.entities.first { $0.name == "Delivery" })
        #expect(
            delivery.relationships.allSatisfy { $0.destination != "RouteSuspension" },
            "No delivery owns, starts or ends a suspension"
        )

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let suspensions = try #require(shift.relationships.first { $0.destination == "RouteSuspension" })
        #expect(
            suspensions.deleteRule == .cascade,
            "A deleted shift takes its own statements about itself with it"
        )
    }

    @Test("The frozen version 15 still describes a store that could record no suspension")
    func versionFifteenHeldNoSuspension() throws {
        let schema = Schema(versionedSchema: DashPilotSchemaV15.self)

        let entities = Set(schema.entities.map(\.name))
        #expect(!entities.contains("RouteSuspension"))
        #expect(entities.contains("VehicleProfile"), "And it keeps everything v15 added")
        #expect(entities.contains("DriverSettings"))

        let shift = try #require(schema.entities.first { $0.name == "Shift" })
        let properties = Set(shift.properties.map(\.name))
        #expect(properties.contains("fuelVehicleName"), "v15 is the version that added the vehicle name")
        #expect(
            shift.relationships.allSatisfy { $0.destination != "RouteSuspension" },
            "The frozen v15 model must describe the store as it was, not as it is now"
        )
    }

    @Test("The step from version 15 is lightweight, because there is nothing truthful to write")
    func theStepIsLightweight() {
        // The tempting stage would read a v15 shift's route, find the gaps and
        // record a suspension for each. A gap is left by a pause, a lost
        // permission, a terminated process and a tunnel, and the rows they leave
        // are identical.
        #expect(DashPilotMigrationPlan.stages.count == DashPilotMigrationPlan.schemas.count - 1)
    }

    // MARK: Migration

    @Test("Every version 15 shift reaches version 16 with its route intact and no suspension invented")
    func migratesFromVersionFifteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()
        let session = UUID()

        do {
            let v15 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV15.self, at: storeURL)
            let context = ModelContext(v15)

            let shift = DashPilotSchemaV15.Shift(
                id: shiftID,
                startedAt: start,
                endedAt: start.addingTimeInterval(2 * 3_600),
                grossEarningsAmount: Decimal(80),
                fuelVehicleName: "Sedan"
            )
            context.insert(shift)

            // A route with a real gap in it, which is exactly the shape a
            // backfill would be tempted to read a suspension out of.
            for step in 0..<5 {
                context.insert(
                    DashPilotSchemaV15.RouteSample(
                        shift: shift,
                        timestamp: start.addingTimeInterval(60 + Double(step) * 20),
                        latitude: 40.0 + Double(step) * 100 / 111_320,
                        longitude: -75,
                        horizontalAccuracy: 8,
                        captureSessionID: session
                    )
                )
            }
            let secondSession = UUID()
            for step in 0..<5 {
                context.insert(
                    DashPilotSchemaV15.RouteSample(
                        shift: shift,
                        timestamp: start.addingTimeInterval(3_600 + Double(step) * 20),
                        latitude: 40.0 + (5_000 + Double(step) * 100) / 111_320,
                        longitude: -75,
                        horizontalAccuracy: 8,
                        captureSessionID: secondSession
                    )
                )
            }
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.grossEarnings == Money(minorUnits: 8_000), "The v15 guarantees still hold")
        #expect(shift.fuelVehicleName == "Sedan")
        #expect(shift.routeSampleCount == 10, "Every position carries over")

        #expect(
            shift.routeSuspensions.isEmpty,
            "A gap is not evidence that anybody parked, and no build that wrote this store could say so"
        )
        #expect(shift.completedSuspendedTime == RouteSuspendedTime.none)
        #expect(try context.fetch(FetchDescriptor<RouteSuspension>()).isEmpty)

        // And the route reads exactly as it read before: same segments, same
        // gap, same partial wording.
        let distance = shift.recordedDistance()
        #expect(distance.segmentCount == 2)
        #expect(distance.gapCount >= 1)
        #expect(
            RouteQuality(distance, suspendedTime: shift.completedSuspendedTime ?? .none)
                .partialExplanation?.contains("more miles were driven than were recorded") == true,
            "A shift recorded before the driver could say they had parked genuinely never said it"
        )
    }

    @Test("A version 14 store still reaches the current version, recording nothing about parking")
    func migratesFromVersionFourteen() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        let shiftID = UUID()

        do {
            let v14 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV14.self, at: storeURL)
            let context = ModelContext(v14)
            context.insert(
                DashPilotSchemaV14.Shift(
                    id: shiftID,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(3 * 3_600),
                    grossEarningsAmount: Decimal(90)
                )
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

        #expect(shift.id == shiftID)
        #expect(shift.grossEarnings == Money(minorUnits: 9_000))
        #expect(shift.fuelVehicleName == nil, "The v15 guarantees still hold")
        #expect(shift.routeSuspensions.isEmpty)
        #expect(try context.fetch(FetchDescriptor<VehicleProfile>()).isEmpty)
    }

    @Test("Deleting a shift takes its suspensions with it")
    func deletingAShiftRemovesItsSuspensions() throws {
        let (storeURL, cleanUp) = try makeStoreURL()
        defer { cleanUp() }

        do {
            let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
            let shifts = ShiftService(context: context)
            let shift = try shifts.startShift(at: start)
            try shifts.parkActiveShift(at: start.addingTimeInterval(600))
            try shifts.resumeDrivingOnActiveShift(at: start.addingTimeInterval(1_200))
            try shifts.endActiveShift(at: start.addingTimeInterval(3_600))

            #expect(try context.fetch(FetchDescriptor<RouteSuspension>()).count == 1)
            try shifts.deleteCompletedShift(shift)
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        #expect(try context.fetch(FetchDescriptor<Shift>()).isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<RouteSuspension>()).isEmpty,
            "No row is left describing a shift that is gone"
        )
    }
}
