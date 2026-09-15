import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What an export says about a figure the driver expected, and everywhere it
/// deliberately says nothing.
///
/// The contract decision under test has two halves and both are asserted rather
/// than described: the JSON form carries the expected amount on the delivery
/// that holds it, and the CSV form does not carry it at all. A spreadsheet
/// column is a thing people sum, and an amount that is explicitly not earnings
/// sitting beside one that is would be summed as though it were.
///
/// Every amount and every name is invented.
@MainActor
@Suite("Expected delivery earnings export")
struct ExpectedDeliveryEarningsExportTests {
    private let encoder = ExportDocumentEncoder()

    private func document(
        _ fixture: ExportFixture,
        scope: ExportScope,
        shifts: [Shift],
        summary: PeriodExportSummary? = nil
    ) throws -> ExportDocument {
        ExportDocument(
            scope: scope,
            shifts: try shifts.map(fixture.exportRecord),
            summary: summary,
            exportedAt: ExportFixture.start
        )
    }

    private func object(_ document: ExportDocument) throws -> [String: Any] {
        let data = try encoder.json(for: document)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func deliveries(in document: ExportDocument) throws -> [[String: Any]] {
        let object = try object(document)
        let shift = try #require((object["shifts"] as? [[String: Any]])?.first)
        return try #require(shift["deliveries"] as? [[String: Any]])
    }

    // MARK: JSON

    @Test("The JSON form carries an expected amount beside the recorded one, never instead of it")
    func jsonCarriesBothAmounts() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        // Expected more than it paid, so the two figures cannot be mistaken for
        // one value written twice.
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "6.25", expected: "8.50")

        let encoded = try #require(try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift])).first)

        #expect(encoded["grossEarnings"] as? String == "6.25")
        #expect(encoded["expectedEarnings"] as? String == "8.50")
    }

    @Test("A delivery with an expectation and no recorded amount exports exactly that")
    func jsonKeepsAnUnconfirmedExpectation() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(in: shift, acceptedAfter: 300, expected: "8.50")
        try fixture.cancelled(in: shift, acceptedAfter: 3_000, expected: "9.75")

        let encoded = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(encoded.count == 2)
        for delivery in encoded {
            #expect(delivery["grossEarnings"] is NSNull, "An expectation is not a recorded amount")
            #expect(delivery["expectedEarnings"] is String)
        }
        #expect(encoded[1]["state"] as? String == DeliveryState.cancelled.rawValue)
        #expect(encoded[1]["expectedEarnings"] as? String == "9.75", "A cancelled order's expectation is kept")
    }

    @Test("An absent expectation is an explicit null, like every other missing value")
    func jsonWritesAnExplicitNull() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "14.75")
        try fixture.delivered(in: shift, acceptedAfter: 3_000, expected: "8.50")

        let encoded = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(encoded[0]["expectedEarnings"] is NSNull, "Never omitted, and never a zero")
        #expect(Set(encoded[0].keys) == Set(encoded[1].keys), "Every delivery record is the same shape")
    }

    @Test("No shift field and no summary figure is derived from an expectation")
    func expectationsReachNoTotal() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "6.25", expected: "8.50")
        try fixture.delivered(in: shift, acceptedAfter: 3_000, expected: "40.00")

        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let metrics = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: shift.recordedDistance())],
            in: period
        )
        let document = try document(
            fixture,
            scope: .period(period),
            shifts: [shift],
            summary: PeriodExportSummary(metrics)
        )

        let object = try object(document)
        let encodedShift = try #require((object["shifts"] as? [[String: Any]])?.first)
        let summary = try #require(object["summary"] as? [String: Any])

        // The shift's own amount, and no expected counterpart to it.
        #expect(encodedShift["grossEarnings"] as? String == "100.00")
        #expect(encodedShift["expectedEarnings"] == nil, "A shift has no expected amount, and gains none here")

        // No key anywhere outside a delivery record mentions an expectation, and
        // no total is the sum of one.
        let shiftKeys = Set(encodedShift.keys).subtracting(["deliveries"])
        for key in shiftKeys {
            #expect(!key.lowercased().contains("expect"), "No expected figure on a shift: \(key)")
        }
        for key in summary.keys {
            #expect(!key.lowercased().contains("expect"), "No expected figure in a summary: \(key)")
        }

        // The delivery subtotal is the one recorded amount, not the expectations
        // beside it and not their sum.
        let deliveryEarnings = try #require(summary["deliveryEarnings"] as? [String: Any])
        #expect(deliveryEarnings["recordedTotal"] as? String == "6.25")
    }

    // MARK: CSV

    @Test("The CSV form is unchanged: 35 columns, and none of them is an expectation")
    func csvCarriesNoExpectation() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "6.25", expected: "8.50")

        let text = try #require(
            String(data: try encoder.csv(for: try document(fixture, scope: .shift(shift.id), shifts: [shift])), encoding: .utf8)
        )
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: true)
        let header = try #require(lines.first).split(separator: ",", omittingEmptySubsequences: false)

        // The count has moved twice since: `deliveryOfferNumber` at version 3,
        // and three tip columns at version 4. What this test asserts is
        // unchanged: no column of this table is an expectation.
        #expect(
            header.count == ExportDocumentEncoder.columns.count,
            "The column count is the contract a positional reader depends on"
        )
        for column in header {
            #expect(!column.lowercased().contains("expect"), "No expected column: \(column)")
        }

        // The recorded amount is there, and the expectation is nowhere in the
        // file at all, neither as a column nor as a stray value.
        #expect(text.contains("6.25"))
        #expect(!text.contains("8.50"), "The expected figure does not reach a spreadsheet")

        let row = try #require(lines.dropFirst().first).split(separator: ",", omittingEmptySubsequences: false)
        #expect(row.count == header.count, "Every row matches the header")
    }
}
