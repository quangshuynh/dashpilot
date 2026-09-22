import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What an export says about tips a delivery received outside the platform's own
/// amount, and what the version number had to become to say it.
///
/// Two contract decisions are under test. **The tips travel as individual
/// records** in JSON, each with its method and the moment it was recorded,
/// because a tip is three facts and a summed figure would carry one of them.
/// And **`grossEarnings` is not redefined**: it is still the platform-recorded
/// amount every previous file stated, with the new total beside it rather than
/// inside it, so a consumer summing the old field is still summing what its name
/// says.
///
/// Every amount, offset and name is invented.
@MainActor
@Suite("Delivery tip export")
struct DeliveryTipExportTests {
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

    /// A shift of three deliveries: one with two tips, one with none, and one
    /// carrying a tip and no platform amount at all.
    private func tippedShift(_ fixture: ExportFixture) throws -> Shift {
        let shift = try fixture.completedShift(earnings: "100.00")

        let tipped = try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "10.00")
        try fixture.tip("3.00", .cash, on: tipped, recordedAfter: 2_000)
        try fixture.tip("5.00", .platform, on: tipped, recordedAfter: 5_400)

        try fixture.delivered(in: shift, acceptedAfter: 3_600, earnings: "6.25")

        let untipped = try fixture.delivered(in: shift, acceptedAfter: 7_200)
        try fixture.tip("4.00", .cash, on: untipped, recordedAfter: 9_000)

        return shift
    }

    // MARK: JSON

    @Test("Each tip is its own record, with what it was, how it arrived and when it was recorded")
    func jsonCarriesEachTip() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        let tips = try #require(records[0]["additionalTips"] as? [[String: Any]])
        #expect(tips.count == 2, "Two tips stay two records rather than becoming one figure")

        // Amounts are quoted decimal strings, which is how every amount in this
        // format is written: a JSON number would be read back as a binary float.
        #expect(tips[0]["amount"] as? String == "3.00")
        #expect(tips[0]["method"] as? String == "cash")
        #expect(tips[0]["recordedAt"] as? String == ExportTimestamp.string(shift.startedAt.addingTimeInterval(2_000)))

        #expect(tips[1]["amount"] as? String == "5.00")
        #expect(tips[1]["method"] as? String == "platform")

        #expect(Set(tips[0].keys) == ["id", "amount", "method", "recordedAt"], "And nothing else about a tip")
    }

    @Test("A delivery with no tips carries an empty array rather than a missing key")
    func jsonAlwaysCarriesTheArray() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        let tips = try #require(records[1]["additionalTips"] as? [Any])
        #expect(tips.isEmpty)
        #expect(
            records[1]["additionalTipsTotal"] is NSNull,
            "No tip recorded is not a tip of nothing, so the total is null rather than 0.00"
        )
    }

    @Test("The platform amount is unchanged, and the total sits beside it")
    func jsonKeepsGrossEarningsMeaningWhatItDid() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(
            records[0]["grossEarnings"] as? String == "10.00",
            "Exactly the amount a version 3 file would have carried for this delivery"
        )
        #expect(records[0]["additionalTipsTotal"] as? String == "8.00")
        #expect(records[0]["effectiveEarnings"] as? String == "18.00")
    }

    @Test("A delivery holding tips and no platform amount states no total")
    func jsonRefusesATotalWithoutThePlatformAmount() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(records[2]["grossEarnings"] is NSNull)
        #expect(records[2]["additionalTipsTotal"] as? String == "4.00", "What was recorded is still stated")
        #expect(
            records[2]["effectiveEarnings"] is NSNull,
            "It paid the tip plus an amount nobody wrote down, so there is no total to state"
        )
        #expect(records[2]["effectiveEarningsPerDeliveryHour"] is NSNull)
    }

    @Test("The delivery's hourly figure is renamed and divides what the delivery actually paid")
    func jsonRenamesTheRate() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let records = try deliveries(in: try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(records[0]["grossPerDeliveryHour"] == nil, "The old key is gone rather than redefined")
        let rate = try #require(records[0]["effectiveEarningsPerDeliveryHour"] as? String)

        let delivery = try #require(shift.deliveriesInOrder.first)
        let effectiveRate = try #require(delivery.effectiveEarningsPerDeliveryHour.amount)
        #expect(rate == ExportAmount(effectiveRate).string)

        // The same denominator over the platform amount alone gives a visibly
        // different figure, which is why keeping the old name would have been a
        // change no reader could detect.
        let duration = try #require(delivery.completedDuration)
        let platformOnly = try #require(
            ShiftMetricsCalculator.grossPerHour(of: try fixture.money("10.00"), over: duration)
        )
        #expect(rate != ExportAmount(platformOnly).string)
    }

    @Test("Nothing about a tip reaches the shift or the file's own level")
    func jsonCarriesNothingElseAboutTips() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(object["tips"] == nil, "There is no top-level tips array")
        let shiftObject = try #require((object["shifts"] as? [[String: Any]])?.first)
        for key in shiftObject.keys {
            #expect(!key.lowercased().contains("tip"), "A shift holds no tip figure: \(key)")
        }
        // A shift's own rates still divide the shift's own amount, which no tip
        // has ever been part of.
        #expect(shiftObject["grossEarnings"] as? String == "100.00")
    }

    // MARK: The period summary

    @Test("The period's delivery subtotal adds up what the deliveries actually paid")
    func summaryUsesEffectiveEarnings() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let metrics = PeriodMetricsCalculator().metrics(of: [shift.periodRecord(for: .none)], in: period)

        let document = ExportDocument(
            scope: .period(period),
            shifts: [try fixture.exportRecord(of: shift)],
            summary: PeriodExportSummary(metrics),
            exportedAt: ExportFixture.start
        )
        let object = try object(document)
        let summary = try #require(object["summary"] as? [String: Any])
        let deliveryEarnings = try #require(summary["deliveryEarnings"] as? [String: Any])

        // $18.00 and $6.25. The third delivery records a tip and no platform
        // amount, so it contributes nothing and counts against the coverage.
        #expect(deliveryEarnings["recordedTotal"] as? String == "24.25")
        #expect(deliveryEarnings["contributingDeliveryCount"] as? Int == 2)
        #expect(deliveryEarnings["totalDeliveryCount"] as? Int == 3)
    }

    // MARK: CSV

    @Test("The CSV carries the count, the total and what the delivery paid, and no individual tip")
    func csvCarriesTheThreeColumns() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let data = try encoder.csv(for: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: true)
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)

        #expect(header.contains("deliveryAdditionalTipCount"))
        #expect(header.contains("deliveryAdditionalTipsTotal"))
        #expect(header.contains("deliveryEffectiveEarnings"))
        #expect(header.contains("deliveryEffectiveEarningsPerDeliveryHour"))
        #expect(!header.contains("deliveryGrossPerDeliveryHour"), "The renamed column is gone rather than redefined")
        #expect(header.count == Set(header).count, "No column name is repeated")

        func field(_ name: String, inRow row: Int) throws -> String {
            let index = try #require(header.firstIndex(of: name))
            let fields = lines[row].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return fields[index]
        }

        #expect(try field("deliveryGrossEarnings", inRow: 1) == "10.00")
        #expect(try field("deliveryAdditionalTipCount", inRow: 1) == "2")
        #expect(try field("deliveryAdditionalTipsTotal", inRow: 1) == "8.00")
        #expect(try field("deliveryEffectiveEarnings", inRow: 1) == "18.00")

        // A count of recorded facts, so zero is the honest value; the total
        // beside it is an empty cell rather than 0.00.
        #expect(try field("deliveryAdditionalTipCount", inRow: 2) == "0")
        #expect(try field("deliveryAdditionalTipsTotal", inRow: 2) == "")
        #expect(try field("deliveryEffectiveEarnings", inRow: 2) == "6.25")

        // Tips and no platform amount: the total is empty rather than the tips.
        #expect(try field("deliveryGrossEarnings", inRow: 3) == "")
        #expect(try field("deliveryAdditionalTipsTotal", inRow: 3) == "4.00")
        #expect(try field("deliveryEffectiveEarnings", inRow: 3) == "")
    }

    @Test("The existing columns stay where a positional reader already reads them")
    func csvAppendsRatherThanInserts() throws {
        let columns = ExportDocumentEncoder.columns

        #expect(columns.count == 41, "36 before tips, three appended by them, and two by parking")
        #expect(
            Array(columns[36...38]) == [
                "deliveryAdditionalTipCount", "deliveryAdditionalTipsTotal", "deliveryEffectiveEarnings"
            ],
            "Appended, because inserting one moves every column after it"
        )
        #expect(
            Array(columns.suffix(2)) == ["shiftRouteSuspensionCount", "shiftRouteSuspendedSeconds"],
            "And the two appended after them left the tip columns exactly where they were"
        )
        #expect(columns[35] == "deliveryOfferNumber", "The previous last column is still the 36th")
        #expect(columns.firstIndex(of: "deliveryGrossEarnings") == 33, "And the amount column has not moved")
    }

    @Test("No individual tip amount, method or time reaches the CSV")
    func csvCarriesNoIndividualTip() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "100.00")
        let delivery = try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "10.00")
        // Two tips whose amounts appear nowhere else in the file, so finding
        // either one would mean a column had leaked it.
        try fixture.tip("3.11", .cash, on: delivery, recordedAfter: 2_000)
        try fixture.tip("5.13", .platform, on: delivery, recordedAfter: 5_400)

        let data = try encoder.csv(for: try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(!text.contains("3.11"))
        #expect(!text.contains("5.13"))
        #expect(!text.lowercased().contains("cash"))
        #expect(text.contains("8.24"), "Only the total they come to, which is a thing a spreadsheet can sum")
        #expect(text.contains("18.24"), "And what the delivery therefore paid")
    }

    @Test("The format picker says where the individual tips are")
    func csvExplanationSaysWhatIsMissing() {
        let explanation = ExportFileFormat.csv.explanation.lowercased()
        #expect(explanation.contains("tips"))
        #expect(explanation.contains("total"))
        #expect(ExportFileFormat.json.explanation.lowercased().contains("tip"))
    }

    // MARK: The version decision

    @Test("A rename and a redefinition moved the format version to 4")
    func versionMoved() throws {
        let fixture = try ExportFixture()
        let shift = try tippedShift(fixture)
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(ExportFormat.version == 4)
        #expect(object["formatVersion"] as? Int == 4)
        #expect(
            ExportFormat.version != Int(DashPilotSchemaV13.versionIdentifier.major),
            "The file's version and the store's schema version are unrelated numbers"
        )
    }
}
