import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Which recorded pickup waits a typical wait is taken over, and how the ones
/// left out are accounted for.
///
/// **The population, named once:** every recorded wait except those whose
/// pickup was recorded automatically, by Resume Driving under the Park and
/// Resume workflow or by Park under the setting that workflow replaced. That
/// is the driver's own Picked Up step on any surface, plus pickups recorded
/// before DashPilot kept how (unknown), which were counted before and still
/// are. Automated waits are counted apart, by kind, and said beside every
/// figure they are left out of. Nothing is scaled, corrected, estimated or
/// replaced.
@Suite("Pickup wait provenance policy")
struct PickupWaitProvenancePolicyTests {
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func sample(_ minutes: Double, _ provenance: PickupProvenance?, index: Int = 0) -> PickupWaitSample {
        PickupWaitSample(
            duration: minutes * 60,
            pickedUpAt: base.addingTimeInterval(Double(index) * 3_600),
            provenance: provenance
        )
    }

    private func metrics(_ samples: [PickupWaitSample]) -> PickupWaitMetrics {
        PickupWaitCalculator().metrics(of: samples)
    }

    // MARK: The population

    @Test("Park-recorded waits are left out of every figure and counted apart")
    func parkWaitsAreCountedApart() {
        let result = metrics([
            sample(4, .manual, index: 0), sample(6, .manual, index: 1), sample(7, .manual, index: 2),
            sample(0.5, .parkAutomation, index: 3), sample(3, .parkAutomation, index: 4)
        ])

        #expect(result.sampleCount == 3)
        #expect(result.medianDuration == 360, "6 minutes, the manual median, where all five would read 4")
        #expect(result.shortestDuration == 240, "A Park wait is not the shortest wait")
        #expect(result.longestDuration == 420)
        #expect(result.mostRecentSampleAt == base.addingTimeInterval(2 * 3_600))
        #expect(result.parkRecordedPickupCount == 2)
    }

    @Test("Unknown provenance is counted, as it was before provenance was recorded")
    func unknownIsCounted() {
        let result = metrics([sample(8, nil), sample(10, .manual, index: 1), sample(1, .parkAutomation, index: 2)])

        #expect(result.sampleCount == 2)
        #expect(result.medianDuration == 540)
        #expect(result.parkRecordedPickupCount == 1)
    }

    @Test("A manual wait of zero still counts, and Park waits are not zeros either")
    func missingIsNotZero() {
        let result = metrics([sample(0, .manual), sample(0, .parkAutomation, index: 1)])
        #expect(result.sampleCount == 1)
        #expect(result.medianDuration == 0)
        #expect(result.parkRecordedPickupCount == 1)
    }

    @Test("Only Park-recorded waits: no figure at all, never a zero, and the count is still said")
    func onlyParkRecordedIsNoFigure() {
        let result = metrics([sample(1, .parkAutomation), sample(2, .parkAutomation, index: 1)])

        #expect(result.availability == .noRecordedWaits)
        #expect(result.medianDuration == nil)
        #expect(result.typicalDuration == nil)
        #expect(result.shortestDuration == nil)
        #expect(result.parkRecordedPickupCount == 2)
        #expect(
            result.insufficientHistoryExplanation?.contains("No delivery here recorded both") == false,
            "They did record both, so the screen must not say they did not"
        )
        #expect(result.spokenStatement.contains("2 pickups recorded when you parked are not counted"))
    }

    @Test("Resume-recorded waits are left out and counted apart from Park's")
    func resumeWaitsAreCountedApart() {
        let result = metrics([
            sample(4, .manual, index: 0), sample(6, .manual, index: 1), sample(7, .manual, index: 2),
            sample(9, .resumeAutomation, index: 3), sample(14, .resumeAutomation, index: 4),
            sample(0.5, .parkAutomation, index: 5)
        ])

        #expect(result.sampleCount == 3)
        #expect(result.medianDuration == 360, "The manual median, where all six would read 6:30")
        #expect(result.longestDuration == 420, "A Resume wait is not the longest wait")
        #expect(result.resumeRecordedPickupCount == 2)
        #expect(result.parkRecordedPickupCount == 1)
        #expect(result.automatedPickupCount == 3)
        #expect(result.spokenStatement.hasSuffix(
            "3 pickups recorded when you parked or resumed driving are not counted: they end then, not at the handover."
        ))
    }

    @Test("Only Resume-recorded waits: no figure, the count said, and the screen does not claim nothing was recorded")
    func onlyResumeRecordedIsNoFigure() {
        let result = metrics([sample(9, .resumeAutomation), sample(12, .resumeAutomation, index: 1)])

        #expect(result.availability == .noRecordedWaits)
        #expect(result.typicalDuration == nil)
        #expect(result.resumeRecordedPickupCount == 2)
        #expect(result.insufficientHistoryExplanation?.contains("No delivery here recorded both") == false)
        #expect(result.spokenStatement.contains("2 pickups recorded when you resumed driving are not counted"))
    }

    @Test("A wait Park began and the driver's own Picked Up step ended counts: it is keyed on the pickup")
    func automatedArrivalManualPickupCounts() {
        #expect(sample(8, .manual).countsTowardTypicalWait, "Park's arrival does not make the wait automated")
        #expect(!sample(8, .resumeAutomation).countsTowardTypicalWait)
    }

    @Test("A sample keeps its recorded duration whoever recorded it: nothing is scaled or replaced")
    func noFabricatedWait() {
        let parked = sample(0.5, .parkAutomation)
        #expect(parked.duration == 30)
        #expect(parked.countsTowardTypicalWait == false)
        #expect(sample(0.5, .manual).countsTowardTypicalWait)
        #expect(sample(0.5, nil).countsTowardTypicalWait)
    }

    // MARK: Wording

    @Test("The left-out waits are said in singular and plural, and not at all when there are none")
    func exclusionWording() {
        #expect(PickupWaitMetrics.automatedPickupStatement(parkRecorded: 0, resumeRecorded: 0) == nil)
        #expect(
            PickupWaitMetrics.automatedPickupStatement(parkRecorded: 1, resumeRecorded: 0)
                == "1 pickup recorded when you parked is not counted: it ends when you parked, not at the handover."
        )
        #expect(
            PickupWaitMetrics.automatedPickupStatement(parkRecorded: 3, resumeRecorded: 0)
                == "3 pickups recorded when you parked are not counted: they end when you parked, not at the handover."
        )
        #expect(
            PickupWaitMetrics.automatedPickupStatement(parkRecorded: 0, resumeRecorded: 1)
                == "1 pickup recorded when you resumed driving is not counted: it ends when you drove off, "
                + "not at the handover."
        )
        #expect(
            PickupWaitMetrics.automatedPickupStatement(parkRecorded: 0, resumeRecorded: 2)
                == "2 pickups recorded when you resumed driving are not counted: they end when you drove off, "
                + "not at the handover."
        )
        #expect(
            PickupWaitMetrics.automatedPickupStatement(parkRecorded: 1, resumeRecorded: 2)
                == "3 pickups recorded when you parked or resumed driving are not counted: they end then, "
                + "not at the handover."
        )
        #expect(metrics([sample(5, .manual)]).automatedPickupStatement == nil)
    }

    @Test("VoiceOver hears the exclusion with the figure it qualifies")
    func spokenIncludesExclusion() {
        let result = metrics([
            sample(4, .manual), sample(6, .manual, index: 1), sample(1, .parkAutomation, index: 2)
        ])
        #expect(result.spokenStatement.hasPrefix("Typical recorded pickup wait, "))
        #expect(result.spokenStatement.hasSuffix("1 pickup recorded when you parked is not counted: it ends when you parked, not at the handover."))
    }

    @Test("Nothing says DashPilot knows when the order was handed over")
    func noHandoverClaim() {
        for count in 1...3 {
            for (park, resume) in [(count, 0), (0, count), (count, count)] {
                let statement = PickupWaitMetrics.automatedPickupStatement(parkRecorded: park, resumeRecorded: resume) ?? ""
                #expect(!statement.contains("detected"))
                #expect(!statement.contains("estimate"))
            }
        }
        #expect(PickupProvenance.pickedUpEventTitle(.resumeAutomation) == "Picked up (recorded by Resume Driving)")
        #expect(PickupProvenance.pickedUpEventTitle(.parkAutomation) == "Picked up (recorded by Park)")
        #expect(PickupProvenance.pickedUpEventTitle(.manual) == "Picked up")
        #expect(PickupProvenance.pickedUpEventTitle(nil) == "Picked up", "Unknown is not labelled as anything")
    }
}

/// The same policy through the store: the place screen, a period summary, the
/// export, a correction and a change of setting.
@MainActor
@Suite("Pickup wait provenance policy through the store")
struct PickupWaitProvenanceStorePolicyTests {
    private let start: Date
    private let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        self.calendar = calendar
        start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 4)))
    }

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private struct Store {
        let context: ModelContext
        let place: PickupPlace
        let shift: Shift
        let manual: [Delivery]
        let parked: Delivery
    }

    /// One finished shift at one place: two manual pickups (6 and 8 minutes)
    /// and one Park pickup half a minute after its arrival, with the setting
    /// on while it was recorded.
    private func makeStore() throws -> Store {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        let shifts = ShiftService(context: context)
        let service = DeliveryService(context: context)
        let places = PickupPlaceService(context: context)
        let shift = try shifts.startShift(at: start)

        var manual: [Delivery] = []
        for (index, wait) in [6.0, 8.0].enumerated() {
            let offset = Double(index) * 40
            let delivery = try service.startDelivery(at: at(offset))
            try places.assignPlace(named: "Synthetic Dumplings", to: delivery, at: at(offset))
            try service.markArrivedAtPickup(delivery, at: at(offset + 5))
            try service.markPickedUp(delivery, at: at(offset + 5 + wait))
            try service.markDelivered(delivery, at: at(offset + 30))
            manual.append(delivery)
        }

        // A pickup the retired Park-when-parking setting recorded. Nothing
        // records one any more, so it is written with its provenance directly,
        // as stores from that build hold it.
        let parked = try service.startDelivery(at: at(90))
        let place = try places.assignPlace(named: "Synthetic Dumplings", to: parked, at: at(90))
        try service.markArrivedAtPickup(parked, at: at(100))
        try service.markPickedUp(parked, at: at(100.5), recordedBy: .parkAutomation)
        try shifts.parkActiveShift(at: at(100.5))
        try shifts.resumeDrivingOnActiveShift(at: at(115))
        try service.markDelivered(parked, at: at(130))
        try shifts.endActiveShift(at: at(140))
        return Store(context: context, place: place, shift: shift, manual: manual, parked: parked)
    }

    private func periodMetrics(_ store: Store) throws -> PeriodMetrics {
        try periodMetrics(store.shift)
    }

    private func periodMetrics(_ shift: Shift) throws -> PeriodMetrics {
        let period = try #require(ReportingPeriod(unit: .day, containing: start, calendar: calendar))
        let record = shift.periodRecord(for: shift.recordedDistance())
        return PeriodMetricsCalculator().metrics(of: [record], in: period)
    }

    @Test("A place's typical wait and its listed waits are the same population")
    func placeUsesThePolicy() throws {
        let store = try makeStore()
        let metrics = store.place.pickupWaitMetrics()

        #expect(metrics.sampleCount == 2)
        #expect(metrics.medianDuration == 420)
        #expect(metrics.parkRecordedPickupCount == 1)
        #expect(store.place.pickupWaitSamples.count == 3, "The wait is still there to be read")
        #expect(store.place.countedPickupWaitSamples.map(\.duration) == [360, 480])
    }

    @Test("A period's median uses the same rule and says what it left out")
    func periodUsesThePolicy() throws {
        let store = try makeStore()
        let metrics = try periodMetrics(store)

        #expect(metrics.pickupWaitSampleCount == 2)
        #expect(metrics.medianPickupWait == 420)
        #expect(metrics.parkRecordedPickupCount == 1)
        #expect(metrics.pickupWaitBasisStatement == "Based on 2 recorded pickups")
        #expect(metrics.automatedPickupStatement?.hasPrefix("1 pickup recorded when you parked") == true)
        #expect(metrics.spokenPickupWaitStatement.contains("1 pickup recorded when you parked is not counted"))
    }

    @Test("Turning the setting off rewrites nothing that was already recorded")
    func settingsDoNotRewriteHistory() throws {
        let store = try makeStore()
        let before = store.place.pickupWaitMetrics()

        try SettingsService(context: store.context).setUsesParkAndResumeForPickups(true)
        #expect(store.place.pickupWaitMetrics() == before)
        #expect(store.parked.pickupProvenance == .parkAutomation)

        try SettingsService(context: store.context).setUsesParkAndResumeForPickups(false)
        #expect(store.place.pickupWaitMetrics() == before, "Nor does turning it on again")
        #expect(store.manual.allSatisfy { $0.pickupProvenance == .manual })
    }

    @Test("Correcting a manual pickup moves the median at once; correcting Park's moves its wait and not its population")
    func correctionsRederive() throws {
        let store = try makeStore()
        let service = DeliveryService(context: store.context)

        let manual = store.manual[0]
        try service.correctRecordedTimes(manual, to: DeliveryLifecycleRecord(manual).replacing(.pickedUp, with: at(15)))
        #expect(store.place.pickupWaitMetrics().medianDuration == 540, "10 and 8 minutes now")

        try service.correctRecordedTimes(
            store.parked,
            to: DeliveryLifecycleRecord(store.parked).replacing(.pickedUp, with: at(109))
        )
        #expect(store.parked.pickupWait == 540)
        let after = store.place.pickupWaitMetrics()
        #expect(after.sampleCount == 2, "A correction is not a manual recording")
        #expect(after.parkRecordedPickupCount == 1)
        #expect(after.medianDuration == 540)
    }

    // MARK: Export

    private func exportedDeliveries(_ store: Store) throws -> [[String: Any]] {
        let document = ExportDocument(
            scope: .allHistory,
            shifts: [try store.shift.exportRecord(for: store.shift.recordedDistance())],
            summary: nil,
            exportedAt: start
        )
        let data = try ExportDocumentEncoder().json(for: document)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let shift = try #require((object["shifts"] as? [[String: Any]])?.first)
        return try #require(shift["deliveries"] as? [[String: Any]])
    }

    @Test("Each delivery exports how its pickup was recorded, beside its unchanged wait")
    func jsonCarriesProvenance() throws {
        let store = try makeStore()
        let deliveries = try exportedDeliveries(store)

        #expect(deliveries.map { $0["pickupRecordedBy"] as? String } == ["manual", "manual", "parkAutomation"])
        #expect(deliveries[2]["pickupWaitSeconds"] as? Int == 30, "The recorded interval, not an estimate")
    }

    @Test("A migrated pickup exports as unknown and still counts; a delivery with no pickup exports null")
    func migratedPickupExportsUnknown() throws {
        let directory = URL.temporaryDirectory
            .appending(path: "DashPilotProvenancePolicyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "DashPilot.store")

        do {
            let v17 = try ModelContainerFactory.makeContainer(versionedSchema: DashPilotSchemaV17.self, at: storeURL)
            let context = ModelContext(v17)
            let shift = DashPilotSchemaV17.Shift(startedAt: start, endedAt: at(60))
            context.insert(shift)
            context.insert(
                DashPilotSchemaV17.Delivery(
                    shift: shift, acceptedAt: at(1), arrivedAtPickupAt: at(2), pickedUpAt: at(9), deliveredAt: at(20)
                )
            )
            context.insert(
                DashPilotSchemaV17.Delivery(shift: shift, acceptedAt: at(21), arrivedAtPickupAt: at(25), cancelledAt: at(30))
            )
            try context.save()
        }

        let context = ModelContext(try ModelContainerFactory.makeContainer(at: storeURL))
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let document = ExportDocument(
            scope: .allHistory,
            shifts: [try shift.exportRecord(for: shift.recordedDistance())],
            summary: nil,
            exportedAt: start
        )
        let data = try ExportDocumentEncoder().json(for: document)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let deliveries = try #require((object["shifts"] as? [[String: Any]])?.first?["deliveries"] as? [[String: Any]])

        #expect(deliveries.count == 2)
        #expect(deliveries[0]["pickupRecordedBy"] as? String == "unknown", "Never written as manual")
        #expect(deliveries[1]["pickupRecordedBy"] is NSNull, "No pickup, so nothing to say about one")

        let metrics = try periodMetrics(shift)
        #expect(metrics.pickupWaitSampleCount == 1, "Unknown provenance is counted, as before")
        #expect(metrics.parkRecordedPickupCount == 0)
    }

    @Test("The CSV appends one column and moves none")
    func csvAppendsOneColumn() throws {
        let store = try makeStore()
        let document = ExportDocument(
            scope: .allHistory,
            shifts: [try store.shift.exportRecord(for: store.shift.recordedDistance())],
            summary: nil,
            exportedAt: start
        )
        let text = try #require(String(data: try ExportDocumentEncoder().csv(for: document), encoding: .utf8))
        let rows = text.split(separator: "\r\n", omittingEmptySubsequences: true)
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }

        #expect(ExportDocumentEncoder.columns.count == 42)
        #expect(rows[0].last == "deliveryPickupRecordedBy")
        #expect(rows[0][40] == "shiftRouteSuspendedSeconds", "The previous last column has not moved")
        #expect(rows.dropFirst().map(\.last) == ["manual", "manual", "parkAutomation"])
    }

    @Test("The period summary's median is redefined with the screen's, and says what it left out")
    func summaryRedefinition() throws {
        let store = try makeStore()
        let summary = PeriodExportSummary(try periodMetrics(store))
        let data = try JSONEncoder().encode(summary)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let deliveries = try #require(object["deliveries"] as? [String: Any])

        #expect(deliveries["medianPickupWaitSeconds"] as? Int == 420)
        #expect(deliveries["pickupWaitSampleCount"] as? Int == 2)
        #expect(deliveries["parkRecordedPickupCount"] as? Int == 1)
        #expect(deliveries["resumeRecordedPickupCount"] as? Int == 0, "Added by version 6, and none here")
        #expect(ExportFormat.version == 6)
    }
}
