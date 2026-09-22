import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What an export says about the stretches a driver recorded the vehicle as
/// parked, and why the version number did not have to move to say it.
///
/// The contract decision under test: the two figures are **additive**, they sit
/// with the route rather than with the durations, and **nothing subtracts
/// them**. A reader who sums `workingSeconds` over a driver's week gets exactly
/// what they got before; a reader who wondered why one shift's recorded mileage
/// was short now has the one fact that answers it.
///
/// Every amount, offset and coordinate is invented.
@MainActor
@Suite("Route suspension export")
struct RouteSuspensionExportTests {
    private let encoder = ExportDocumentEncoder()

    private func document(_ fixture: ExportFixture, shifts: [Shift]) throws -> ExportDocument {
        ExportDocument(
            scope: .allHistory,
            shifts: try shifts.map(fixture.exportRecord),
            summary: nil,
            exportedAt: ExportFixture.start
        )
    }

    private func shiftObject(_ document: ExportDocument) throws -> [String: Any] {
        let data = try encoder.json(for: document)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require((object["shifts"] as? [[String: Any]])?.first)
    }

    private func route(_ document: ExportDocument) throws -> [String: Any] {
        try #require(try shiftObject(document)["route"] as? [String: Any])
    }

    /// A completed shift holding a route in two sessions and one recorded
    /// suspension between them.
    private func parkedShift(in fixture: ExportFixture) throws -> Shift {
        let shift = try fixture.completedShift(earnings: "80.00")
        fixture.attachRoute(to: shift, sessions: 2)
        fixture.context.insert(
            RouteSuspension(
                shift: shift,
                startedAt: shift.startedAt.addingTimeInterval(600),
                endedAt: shift.startedAt.addingTimeInterval(2_100)
            )
        )
        return shift
    }

    // MARK: JSON

    @Test("A shift that was parked exports the count and the duration, with its route")
    func exportsTheSuspension() throws {
        let fixture = try ExportFixture()
        let shift = try parkedShift(in: fixture)
        let route = try route(try document(fixture, shifts: [shift]))

        #expect(route["suspensionCount"] as? Int == 1)
        #expect(route["suspendedSeconds"] as? Int == 1_500)
        // With the route, because that is the figure they explain.
        #expect(route["isPartial"] as? Bool == true)
        #expect(
            route["segmentCount"] as? Int == 2,
            "The two capture sessions the parking left between them"
        )
    }

    @Test("A shift that was never parked exports zero, not null")
    func exportsZeroForAShiftNeverParked() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "80.00")
        fixture.attachRoute(to: shift)

        let route = try route(try document(fixture, shifts: [shift]))

        #expect(route["suspensionCount"] as? Int == 0)
        #expect(
            route["suspendedSeconds"] as? Int == 0,
            "A shift the driver never parked was parked for no time, which is a measurement"
        )
        #expect(route["suspendedSeconds"] is NSNull == false)
    }

    @Test("Nothing subtracts the parked seconds, in the file or anywhere near it")
    func nothingSubtractsTheParkedSeconds() throws {
        let fixture = try ExportFixture()
        let shift = try parkedShift(in: fixture)
        let object = try shiftObject(try document(fixture, shifts: [shift]))

        // A three-hour shift, a quarter of an hour of it inside a shop.
        #expect(object["elapsedSeconds"] as? Int == 10_800)
        #expect(
            object["workingSeconds"] as? Int == 10_800,
            "Shopping is working: the denominator every rate divides by does not move"
        )
        #expect(object["pausedSeconds"] as? Int == 0)
        #expect(object["pauseCount"] as? Int == 0, "No pause row exists, because parking is not pausing")
    }

    @Test("The suspension appears nowhere but the route, and no summary counts it")
    func appearsNowhereElse() throws {
        let fixture = try ExportFixture()
        let shift = try parkedShift(in: fixture)
        let data = try encoder.json(for: try document(fixture, shifts: [shift]))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let shiftObject = try #require((object["shifts"] as? [[String: Any]])?.first)
        #expect(shiftObject["suspensionCount"] == nil, "It is a fact about the route, and lives there")
        #expect(shiftObject["suspendedSeconds"] == nil)

        for delivery in (shiftObject["deliveries"] as? [[String: Any]]) ?? [] {
            #expect(delivery["suspensionCount"] == nil, "No delivery owns a suspension")
            #expect(delivery["suspendedSeconds"] == nil)
        }

        // And no instant reaches the file. The count and the duration say how
        // much and how often, never when: the minutes a driver spends inside a
        // shop are the same kind of statement about their day a pause is, and
        // the file carries the durations because the driver asked for it.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("suspensions"), "No array of individual stretches")
        #expect(!text.contains("parkedAt"))
    }

    @Test("The format version is unchanged, because both fields are additions")
    func theVersionDoesNotMove() throws {
        let fixture = try ExportFixture()
        let shift = try parkedShift(in: fixture)
        let object = try #require(
            try JSONSerialization.jsonObject(
                with: try encoder.json(for: try document(fixture, shifts: [shift]))
            ) as? [String: Any]
        )

        #expect(object["formatVersion"] as? Int == 4)
        #expect(ExportFormat.version == 4)

        // Nothing existing changed meaning, nothing was removed or renamed, and
        // no enumeration gained a value, which is the format's own rule.
        let route = try #require((object["shifts"] as? [[String: Any]])?.first?["route"] as? [String: Any])
        #expect(
            Set(route.keys) == [
                "status", "isPartial", "recordedDistanceMetres", "recordedDistanceMiles",
                "segmentCount", "gapCount", "usableSampleCount", "usesInferredContinuity",
                "suspensionCount", "suspendedSeconds"
            ]
        )
    }

    // MARK: CSV

    @Test("The CSV appends two columns and moves none")
    func csvAppendsTwoColumns() throws {
        let fixture = try ExportFixture()
        let shift = try parkedShift(in: fixture)
        let data = try encoder.csv(for: try document(fixture, shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let rows = text.split(separator: "\r\n", omittingEmptySubsequences: true)
        let header = try #require(rows.first).split(separator: ",", omittingEmptySubsequences: false)

        #expect(header.count == 41, "39 before this interval, and two appended")
        #expect(header.suffix(2).map(String.init) == ["shiftRouteSuspensionCount", "shiftRouteSuspendedSeconds"])
        // The columns a positional reader already reads are exactly where they
        // were, which is the other half of not bumping the version.
        #expect(header[0] == "shiftStartedAt")
        #expect(header[10] == "shiftRecordedDistanceMetres")
        #expect(header[38] == "deliveryEffectiveEarnings")

        let row = try #require(rows.dropFirst().first).split(separator: ",", omittingEmptySubsequences: false)
        #expect(row.count == 41)
        #expect(row.suffix(2).map(String.init) == ["1", "1500"])
    }

    @Test("Every row of a shift carries the same two figures, as its other shift columns do")
    func csvRepeatsThemPerRow() throws {
        let fixture = try ExportFixture()
        let shift = try parkedShift(in: fixture)
        try fixture.delivered(in: shift, acceptedAfter: 3_000)
        try fixture.delivered(in: shift, acceptedAfter: 6_000)

        let data = try encoder.csv(for: try document(fixture, shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let rows = text.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst()

        #expect(rows.count == 2)
        for row in rows {
            let fields = row.split(separator: ",", omittingEmptySubsequences: false)
            #expect(fields.count == 41)
            #expect(fields.suffix(2).map(String.init) == ["1", "1500"])
        }
    }

    @Test("A shift never parked writes 0 in both columns, never an empty cell")
    func csvWritesZeroForAShiftNeverParked() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "80.00")
        fixture.attachRoute(to: shift)

        let data = try encoder.csv(for: try document(fixture, shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let row = try #require(
            text.split(separator: "\r\n", omittingEmptySubsequences: true).dropFirst().first
        ).split(separator: ",", omittingEmptySubsequences: false)

        #expect(row.suffix(2).map(String.init) == ["0", "0"])
    }
}
