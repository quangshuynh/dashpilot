import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What an export says about which deliveries were accepted together, and
/// everywhere it deliberately says nothing.
///
/// The contract decision under test is that offer membership travels as **one
/// grouping key on the delivery**, in both forms, and that nothing else about an
/// offer is in the file at all. Nesting the deliveries inside an offer object
/// would have moved an existing field, which is a removal to every reader, and
/// the CSV could not have expressed the nesting honestly: its unit is a
/// delivery, one row each.
///
/// Every amount, offset and name is invented.
@MainActor
@Suite("Delivery offer export")
struct DeliveryOfferExportTests {
    private let encoder = ExportDocumentEncoder()

    private func document(
        _ fixture: ExportFixture,
        scope: ExportScope,
        shifts: [Shift]
    ) throws -> ExportDocument {
        ExportDocument(
            scope: scope,
            shifts: try shifts.map(fixture.exportRecord),
            summary: nil,
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

    /// A shift holding one offer of two deliveries and a later offer of one.
    private func groupedShift(_ fixture: ExportFixture) throws -> Shift {
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.deliveredOffer(in: shift, deliveryCount: 2, acceptedAfter: 300, earnings: ["14.75", nil])
        try fixture.delivered(in: shift, acceptedAfter: 5_400, earnings: "6.25")
        return shift
    }

    // MARK: JSON

    @Test("Deliveries accepted together carry the same offer number, and a later offer carries its own")
    func jsonCarriesTheGroupingKey() throws {
        let fixture = try ExportFixture()
        let shift = try groupedShift(fixture)

        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        #expect(records.count == 3)

        let numbers = records.map { $0["number"] as? Int }
        let offerNumbers = records.map { $0["offerNumber"] as? Int }
        #expect(numbers == [1, 2, 3], "Delivery numbers still run across the shift")
        #expect(offerNumbers == [1, 1, 2], "The first two arrived together; the third did not")
    }

    @Test("The file carries no offer object, no offer total and no offer rate")
    func jsonCarriesNothingElseAboutAnOffer() throws {
        let fixture = try ExportFixture()
        let shift = try groupedShift(fixture)
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(object["offers"] == nil, "There is no top-level offers array")
        let shiftObject = try #require((object["shifts"] as? [[String: Any]])?.first)
        #expect(shiftObject["offers"] == nil, "And none on a shift either")
        #expect(shiftObject["offerCount"] == nil)

        // The only offer key anywhere is the one on each delivery.
        let records = try #require(shiftObject["deliveries"] as? [[String: Any]])
        for record in records {
            let offerKeys = record.keys.filter { $0.lowercased().contains("offer") }
            #expect(offerKeys == ["offerNumber"], "Found: \(offerKeys)")
        }
        let shiftKeys = shiftObject.keys.filter { $0.lowercased().contains("offer") }
        #expect(shiftKeys.isEmpty, "Found: \(shiftKeys)")
    }

    @Test("A delivery recording no offer carries an explicit null rather than an invented group")
    func jsonWritesAnExplicitNull() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "40.00")

        // Built directly rather than through a fixture helper, because this is
        // the one shape the app cannot record: a delivery outside any offer.
        let ungrouped = Delivery(shift: shift, acceptedAt: shift.startedAt.addingTimeInterval(300))
        try ungrouped.markArrivedAtPickup(at: shift.startedAt.addingTimeInterval(600))
        try ungrouped.markPickedUp(at: shift.startedAt.addingTimeInterval(900))
        try ungrouped.markDelivered(at: shift.startedAt.addingTimeInterval(1_500))
        fixture.context.insert(ungrouped)

        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let record = try #require(records.first)
        #expect(record.keys.contains("offerNumber"), "The key is always present")
        #expect(record["offerNumber"] is NSNull, "And it is null rather than a number nobody recorded")
    }

    @Test("Nothing a previously exported shift reported changes because offers exist")
    func jsonFiguresAreUnmoved() throws {
        let fixture = try ExportFixture()
        let shift = try groupedShift(fixture)
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let shiftObject = try #require((object["shifts"] as? [[String: Any]])?.first)

        #expect(object["formatVersion"] as? Int == ExportFormat.version, "Offers are not what moved it")
        #expect(shiftObject["grossEarnings"] as? String == "100.00")
        #expect(shiftObject["deliveredCount"] as? Int == 3)
        #expect(shiftObject["cancelledCount"] as? Int == 0)

        // The two deliveries of one offer overlap completely at their start and
        // end 300 seconds apart, so the unioned active time counts their shared
        // minutes **once**: 300 to 2,280 is 1,980 seconds, and the later
        // delivery on its own adds 1,680. Sharing an offer changes nothing about
        // that; it is the same union it always was, and a sum of the three
        // durations would be 5,340.
        let activeSeconds = try #require(shiftObject["deliveryActiveSeconds"] as? Int)
        #expect(activeSeconds == 1_980 + 1_680)

        // And each amount is still on the delivery it was recorded against.
        let records = try #require(shiftObject["deliveries"] as? [[String: Any]])
        let amounts = records.map { $0["grossEarnings"] as? String }
        #expect(amounts == ["14.75", nil, "6.25"])
    }

    // MARK: CSV

    @Test("The CSV carries the grouping key as one appended column")
    func csvAppendsOneColumn() throws {
        let fixture = try ExportFixture()
        let shift = try groupedShift(fixture)

        let data = try encoder.csv(for: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: true)
        let header = try #require(lines.first).split(separator: ",", omittingEmptySubsequences: false)

        #expect(header.count == 36)
        #expect(header.last == "deliveryOfferNumber", "Appended, so no existing column moved")

        // Every column that existed before is still at the index it was at. The
        // first and last of the old set are enough to pin the whole run.
        #expect(header.first == "shiftStartedAt")
        #expect(header[34] == "deliveryGrossPerDeliveryHour")
        #expect(header[23] == "deliveryNumber")

        let rows = lines.dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false) }
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.count == 36 }, "Every row matches the header")
        #expect(rows.map { String($0[23]) } == ["1", "2", "3"])
        #expect(rows.map { String($0[35]) } == ["1", "1", "2"], "Two rows share an offer; the third does not")
    }

    @Test("A delivery recording no offer leaves the cell empty rather than writing a zero")
    func csvLeavesTheCellEmpty() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "40.00")
        let ungrouped = Delivery(shift: shift, acceptedAt: shift.startedAt.addingTimeInterval(300))
        try ungrouped.markArrivedAtPickup(at: shift.startedAt.addingTimeInterval(600))
        try ungrouped.markPickedUp(at: shift.startedAt.addingTimeInterval(900))
        try ungrouped.markDelivered(at: shift.startedAt.addingTimeInterval(1_500))
        fixture.context.insert(ungrouped)

        let data = try encoder.csv(for: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: true)
        let row = try #require(lines.dropFirst().first).split(separator: ",", omittingEmptySubsequences: false)

        #expect(row.count == 36)
        #expect(row[35].isEmpty, "An empty cell, never a 0 a spreadsheet would group by")
    }

    @Test("A shift with no deliveries still writes one row of the right width")
    func csvEmptyShiftRowIsTheRightWidth() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "40.00")

        let data = try encoder.csv(for: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: true)
        let row = try #require(lines.dropFirst().first).split(separator: ",", omittingEmptySubsequences: false)

        #expect(lines.count == 2)
        #expect(
            row.count == ExportDocumentEncoder.columns.count,
            "The empty delivery fields kept pace with the column list"
        )
    }

    // MARK: The format's own statement

    @Test("Offer grouping did not move the version, and the CSV explanation says the column is there")
    func contractIsStated() {
        // The format is at 4 now, moved by additional tips. Offer grouping is
        // still not what moved it: an added field and an appended column are
        // not a bump, which is the claim this suite has always made.
        #expect(ExportFormat.version == 4)
        #expect(ExportFileFormat.csv.explanation.lowercased().contains("offer"))
    }
}
