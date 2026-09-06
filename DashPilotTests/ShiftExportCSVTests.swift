import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The flat, spreadsheet-friendly file.
///
/// Parsed back into rows and columns rather than matched against a literal, so
/// the assertions are about what a spreadsheet would show rather than about
/// where a comma happens to fall.
@Suite("Shift export CSV")
@MainActor
struct ShiftExportCSVTests {
    private let encoder = ExportDocumentEncoder()

    private func document(_ fixture: ExportFixture, shifts: [Shift]) throws -> ExportDocument {
        ExportDocument(
            scope: .allHistory,
            shifts: try shifts.map(fixture.exportRecord),
            summary: nil,
            exportedAt: ExportFixture.start
        )
    }

    private func rows(_ fixture: ExportFixture, shifts: [Shift]) throws -> [[String: String]] {
        let text = String(decoding: try encoder.csv(for: try document(fixture, shifts: shifts)), as: UTF8.self)
        let records = try Self.parse(text)
        let header = try #require(records.first)
        #expect(header == ExportDocumentEncoder.columns)
        return records.dropFirst().map { record in
            Dictionary(uniqueKeysWithValues: zip(header, record))
        }
    }

    // MARK: Shape

    @Test("The header names every column, once")
    func header() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let text = String(decoding: try encoder.csv(for: try document(fixture, shifts: [shift])), as: UTF8.self)
        let header = try #require(try Self.parse(text).first)

        #expect(Set(header).count == header.count)
        #expect(header.first == "shiftStartedAt")
        // Named for what the figure is, never for what it could be taken for.
        #expect(header.contains("shiftRecordedDistanceMiles"))
        #expect(!header.contains(where: { $0.localizedCaseInsensitiveContains("driven") }))
    }

    @Test("One row per recorded delivery, with the shift's own columns repeated")
    func oneRowPerDelivery() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "86.25")
        try fixture.delivered(in: shift, acceptedAfter: 300)
        try fixture.delivered(in: shift, acceptedAfter: 3_000)

        let rows = try rows(fixture, shifts: [shift])

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0["shiftGrossEarnings"] == "86.25" })
        #expect(rows.map { $0["deliveryNumber"] } == ["1", "2"])
    }

    @Test("A shift with no deliveries still gets a row, with the delivery columns empty")
    func shiftWithoutDeliveries() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")

        let rows = try rows(fixture, shifts: [shift])
        let row = try #require(rows.first)

        #expect(rows.count == 1)
        #expect(row["shiftGrossEarnings"] == "86.25")
        #expect(row["deliveryNumber"] == "")
        #expect(row["deliveryState"] == "")
        #expect(row["deliveryPickupPlaceName"] == "")
    }

    @Test("Several shifts appear in the order the document holds them")
    func severalShifts() throws {
        let fixture = try ExportFixture()
        let first = try fixture.completedShift(startedAfter: 9)
        let second = try fixture.completedShift(startedAfter: 14)

        let rows = try rows(fixture, shifts: [first, second])

        #expect(rows.map { $0["shiftStartedAt"] } == ["2026-06-17T09:00:00Z", "2026-06-17T14:00:00Z"])
    }

    // MARK: Values

    @Test("Timestamps are the same ISO 8601 strings the JSON export writes")
    func timestamps() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3)
        try fixture.delivered(in: shift, acceptedAfter: 300, waitSeconds: 660)

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["shiftStartedAt"] == "2026-06-17T09:00:00Z")
        #expect(row["shiftEndedAt"] == "2026-06-17T12:00:00Z")
        #expect(row["deliveryAcceptedAt"] == "2026-06-17T09:05:00Z")
        #expect(row["deliveryPickedUpAt"] == "2026-06-17T09:19:00Z")
    }

    @Test("Durations are whole seconds, never formatted text")
    func durations() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3)
        try fixture.delivered(in: shift, acceptedAfter: 300, waitSeconds: 660)

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["shiftElapsedSeconds"] == "10800")
        #expect(row["deliveryPickupWaitSeconds"] == "660")
        #expect(row["shiftElapsedSeconds"]?.contains("hr") == false)
    }

    @Test("Money is a plain decimal with no symbol")
    func money() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "90.00")
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "14.75")

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["shiftGrossEarnings"] == "90.00")
        #expect(row["deliveryGrossEarnings"] == "14.75")
        #expect(row["currencyCode"] == "USD")
        #expect(row["shiftGrossPerElapsedHour"] == "30.00")
    }

    @Test("A missing value is an empty cell, never a zero")
    func missingValuesAreEmpty() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.cancelled(in: shift, acceptedAfter: 300)

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        for column in [
            "shiftGrossEarnings",
            "shiftRecordedDistanceMetres", "shiftRecordedDistanceMiles",
            "shiftGrossPerElapsedHour", "shiftGrossPerDeliveryActiveHour", "shiftGrossPerRecordedMile",
            "deliveryPickupWaitSeconds", "deliveryDeliveredAt",
            "deliveryGrossEarnings", "deliveryGrossPerDeliveryHour"
        ] {
            #expect(row[column] == "", "\(column) should be empty when nothing was recorded")
        }

        // The cancelled delivery was open from acceptance until it was
        // cancelled, so the shift does have measurable active time. It is not a
        // missing value, and this is where a change that started treating a
        // cancellation as no work at all would show.
        #expect(row["shiftDeliveryActiveSeconds"] == "900")
        #expect(row["shiftNonDeliverySeconds"] == "9900")
    }

    @Test("A shift with no deliveries has no active time to write, and no zero either")
    func noDeliveriesNoActiveTime() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["shiftDeliveryActiveSeconds"] == "")
        #expect(row["shiftNonDeliverySeconds"] == "")
    }

    @Test("An explicit zero is written as a zero, so it stays distinguishable from a blank")
    func explicitZeroIsWritten() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "0")

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["shiftGrossEarnings"] == "0.00")
    }

    @Test("Route partiality survives as its own columns")
    func routeColumns() throws {
        let fixture = try ExportFixture()
        let partial = try fixture.completedShift(startedAfter: 9)
        fixture.attachRoute(to: partial, sessions: 2)
        let none = try fixture.completedShift(startedAfter: 14)

        let rows = try rows(fixture, shifts: [partial, none])

        #expect(rows[0]["shiftRouteStatus"] == "measured")
        #expect(rows[0]["shiftRouteIsPartial"] == "true")
        #expect(rows[0]["shiftRouteSegmentCount"] == "2")
        #expect(try #require(rows[0]["shiftRecordedDistanceMetres"]).isEmpty == false)

        #expect(rows[1]["shiftRouteStatus"] == "noRouteRecorded")
        #expect(rows[1]["shiftRouteIsPartial"] == "false")
        #expect(rows[1]["shiftRecordedDistanceMetres"] == "")
    }

    @Test("A cancelled delivery is exported as cancelled, not as completed")
    func cancelledDelivery() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.cancelled(in: shift, acceptedAfter: 300)

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["deliveryState"] == "cancelled")
        #expect(row["deliveryCancelledAt"]?.isEmpty == false)
        #expect(row["shiftCancelledCount"] == "1")
        #expect(row["shiftDeliveredCount"] == "0")
    }

    // MARK: The name a driver typed

    @Test(
        "A pickup name that would run as a spreadsheet formula is made safe",
        arguments: ["=NOWHERE()", "+Example", "-Test", "@Diner"]
    )
    func formulaPickupNames(name: String) throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(in: shift, acceptedAfter: 300, place: try fixture.place(named: name))

        let text = String(decoding: try encoder.csv(for: try document(fixture, shifts: [shift])), as: UTF8.self)

        // In the file: guarded and quoted.
        #expect(text.contains("\"'\(name)\""))
        // As a parser hands it to a spreadsheet: text, not a formula.
        let row = try #require(try rows(fixture, shifts: [shift]).first)
        let cell = try #require(row["deliveryPickupPlaceName"])
        #expect(cell == "'\(name)")
        #expect(cell.first != "=")
        #expect(cell.hasSuffix(name))
    }

    @Test("A pickup name with a comma keeps its columns aligned")
    func commaInPickupName() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        try fixture.delivered(
            in: shift,
            acceptedAfter: 300,
            place: try fixture.place(named: "Nowhere Noodles, Downtown"),
            earnings: "14.75"
        )

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["deliveryPickupPlaceName"] == "Nowhere Noodles, Downtown")
        // The column after it is the one a misalignment would corrupt.
        #expect(row["deliveryGrossEarnings"] == "14.75")
    }

    @Test("A pickup name with a quotation mark round-trips")
    func quoteInPickupName() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(
            in: shift,
            acceptedAfter: 300,
            place: try fixture.place(named: "The \"Example\" Diner")
        )

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["deliveryPickupPlaceName"] == "The \"Example\" Diner")
    }

    @Test("A Unicode pickup name is written as itself")
    func unicodePickupName() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(
            in: shift,
            acceptedAfter: 300,
            place: try fixture.place(named: "Nowhere Noodles 🍜 Café")
        )

        let row = try #require(try rows(fixture, shifts: [shift]).first)

        #expect(row["deliveryPickupPlaceName"] == "Nowhere Noodles 🍜 Café")
    }

    // MARK: What CSV deliberately leaves out

    @Test("A period summary is not flattened into the table")
    func noSummaryInCSV() throws {
        let fixture = try ExportFixture()
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let shift = try fixture.completedShift(earnings: "90.00")
        let metrics = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: shift.recordedDistance())],
            in: period
        )
        let document = ExportDocument(
            scope: .period(period),
            shifts: [try fixture.exportRecord(of: shift)],
            summary: PeriodExportSummary(metrics),
            exportedAt: ExportFixture.start
        )

        let text = String(decoding: try encoder.csv(for: document), as: UTF8.self)
        let records = try Self.parse(text)

        // One header and one shift row, and every row the same width: no second
        // table, no key/value preamble, nothing a spreadsheet would misparse.
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.count == ExportDocumentEncoder.columns.count })
        #expect(!text.localizedCaseInsensitiveContains("contributing"))
    }

    // MARK: Parsing

    /// A minimal RFC 4180 reader, so the tests assert on cells rather than on
    /// where a comma landed.
    ///
    /// Deliberately separate from ``CSVWriter``: a round trip through the same
    /// code would prove only that it is self-consistent.
    private static func parse(_ text: String) throws -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        // Unicode scalars rather than `Character`s: Swift treats `\r\n` as one
        // grapheme cluster, so a reader written in `Character`s never sees the
        // carriage return that ends a record.
        let scalars = Array(text.unicodeScalars)
        var index = 0

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }

        func endRecord() {
            endField()
            records.append(fields)
            fields = []
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(scalar)
                }
            } else {
                switch scalar {
                case "\"": inQuotes = true
                case ",": endField()
                case "\r":
                    if index + 1 < scalars.count, scalars[index + 1] == "\n" {
                        endRecord()
                        index += 2
                        continue
                    }
                    field.append(scalar)
                default: field.append(scalar)
                }
            }
            index += 1
        }

        if !field.isEmpty || !fields.isEmpty { endRecord() }
        return records
    }
}
