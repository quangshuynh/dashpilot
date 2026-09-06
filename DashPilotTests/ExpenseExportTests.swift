import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Recorded expenses in an exported file: what the JSON says, what the CSV
/// deliberately does not, and why the format version did not move.
///
/// Every amount, note and place name below is invented.
@MainActor
@Suite("Expense export")
struct ExpenseExportTests {
    private let encoder = ExportDocumentEncoder()

    /// The whole day the fixture's shifts and expenses sit in, in UTC.
    private func day(_ fixture: ExportFixture) throws -> ReportingPeriod {
        try #require(
            ReportingPeriod(unit: .day, containing: fixture.at(9), calendar: ExportFixture.calendar)
        )
    }

    private func object(_ document: ExportDocument) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: try encoder.json(for: document))
        return try #require(parsed as? [String: Any])
    }

    private func text(_ document: ExportDocument) throws -> String {
        String(decoding: try encoder.json(for: document), as: UTF8.self)
    }

    // MARK: The records

    @Test("A period export carries the expenses dated inside it, newest first")
    func periodCarriesItsExpenses() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", category: .fuel, hoursAfterStart: 9.5, note: "Half tank")
        try fixture.expense("6.50", category: .parkingAndTolls, hoursAfterStart: 12)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)

        #expect(document.expenses.count == 2)
        #expect(document.expenses.map(\.amount.string) == ["6.50", "42.10"], "Newest first, as history reads")
        let fuel = try #require(document.expenses.last)
        #expect(fuel.category == .fuel)
        #expect(fuel.note == "Half tank")
        #expect(fuel.currencyCode == "USD")
        #expect(fuel.occurredAt == fixture.at(9.5))
    }

    @Test("An expense outside the period is not in the file")
    func selectsByTheExpenseDate() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        // The next day, during no shift at all.
        try fixture.expense("89.99", category: .maintenance, hoursAfterStart: 30)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)

        #expect(document.expenses.count == 1)
        #expect(document.expenses.first?.amount.string == "42.10")
    }

    @Test("A single shift's file carries no expenses at all")
    func aShiftCarriesNone() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        // Recorded during the shift's own hours, which is exactly the expense a
        // careless implementation would attach to it.
        try fixture.expense("42.10", hoursAfterStart: 10)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .shift(shift.id), exportedAt: ExportFixture.start)

        #expect(document.expenses.isEmpty, "An expense is dated, not attached: no shift owns one")
        // Present and empty rather than absent, so a reader never has to tell
        // "no expenses" from "an older build".
        let object = try object(document)
        #expect(object["expenses"] as? [Any] != nil)
        #expect(document.summary == nil)
    }

    @Test("An all-history export carries every recorded expense")
    func allHistoryCarriesEverything() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        try fixture.expense("89.99", category: .maintenance, hoursAfterStart: 30)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .allHistory, exportedAt: ExportFixture.start)

        #expect(document.expenses.count == 2)
        #expect(document.summary == nil, "All history is not a period, so it has no period summary")
    }

    @Test("A period holding only expenses is exported rather than refused")
    func expensesWithoutShifts() throws {
        let fixture = try ExportFixture()
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)

        #expect(document.shiftCount == 0)
        #expect(document.shifts.isEmpty)
        #expect(document.expenses.count == 1)
        let summary = try #require(document.summary)
        #expect(summary.expenses.recordedTotal?.string == "42.10")
        #expect(summary.netAfterRecordedExpenses.amount == nil, "No recorded earnings to net")
    }

    @Test("A period holding nothing at all is still refused")
    func emptyScopeIsStillRefused() throws {
        let fixture = try ExportFixture()
        try fixture.context.save()

        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
                .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        }
    }

    // MARK: The summary

    @Test("The summary states what was recorded, its categories, and the net after it")
    func summaryFigures() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "86.25")
        // A second shift with no amount, so the coverage in the file is visibly
        // incomplete.
        try fixture.completedShift(startedAfter: 14, lasting: 2)
        try fixture.expense("42.10", category: .fuel, hoursAfterStart: 9.5)
        try fixture.expense("6.50", category: .parkingAndTolls, hoursAfterStart: 12)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let summary = try #require(document.summary)

        #expect(summary.expenses.recordedTotal?.string == "48.60")
        #expect(summary.expenses.recordCount == 2)
        #expect(summary.expenses.currencyCode == "USD")
        #expect(summary.expenses.byCategory.map(\.category) == [.fuel, .parkingAndTolls])
        #expect(summary.expenses.byCategory.first?.total.string == "42.10")

        let net = summary.netAfterRecordedExpenses
        #expect(net.amount?.string == "37.65")
        #expect(net.contributingShiftCount == 1)
        #expect(net.totalShiftCount == 2)
        #expect(net.expenseRecordCount == 2)
    }

    @Test("The gross figures in the file are untouched by the expenses beside them")
    func grossIsUnchanged() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 5, earnings: "100.00")
        fixture.attachRoute(to: shift)
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let summary = try #require(document.summary)

        #expect(summary.earnings.recordedGrossEarnings?.string == "100.00", "Gross stays gross")
        #expect(summary.grossPerElapsedHour.amount?.string == "20.00")
        #expect(document.shifts.first?.grossEarnings?.string == "100.00")
        // Nothing anywhere in the file reports a difference as a shortfall, and
        // no shift-level net exists at all.
        let text = try text(document)
        #expect(!text.contains("shortfall"))
        #expect(!text.lowercased().contains("profit"))
        #expect(!document.shifts.description.lowercased().contains("expense"))
    }

    @Test("A period with no expense recorded writes an absence, never a zero")
    func missingIsNotZeroInTheFile() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let summary = try #require(document.summary)
        let text = try text(document)

        #expect(document.expenses.isEmpty)
        #expect(summary.expenses.recordedTotal == nil)
        #expect(summary.expenses.recordCount == 0)
        #expect(summary.netAfterRecordedExpenses.amount == nil)
        #expect(text.contains("\"recordedTotal\" : null"), "Explicit null, as everywhere else in the file")
        let object = try object(document)
        #expect((object["expenses"] as? [Any])?.isEmpty == true, "An empty array, not a missing key")
    }

    // MARK: The JSON shape

    @Test("An expense is written with the four facts the driver entered")
    func expenseKeys() throws {
        let fixture = try ExportFixture()
        try fixture.expense("42.10", category: .fuel, hoursAfterStart: 9.5, note: "Half tank")
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .allHistory, exportedAt: ExportFixture.start)
        let object = try object(document)
        let expenses = try #require(object["expenses"] as? [[String: Any]])
        let expense = try #require(expenses.first)

        #expect(Set(expense.keys) == ["id", "occurredAt", "category", "amount", "currencyCode", "note"])
        #expect(expense["category"] as? String == "fuel")
        // A decimal string, never a JSON number: a Decimal encoded as a number is
        // re-read as a double outside DashPilot, where nothing can notice.
        #expect(expense["amount"] as? String == "42.10")
        #expect(expense["occurredAt"] as? String == "2026-06-17T09:30:00Z")
        #expect(expense["note"] as? String == "Half tank")
        // No attribution, in any form.
        #expect(!expense.keys.contains { $0.lowercased().contains("shift") })
        #expect(!expense.keys.contains { $0.lowercased().contains("delivery") })
    }

    @Test("An expense with no note writes an explicit null")
    func absentNote() throws {
        let fixture = try ExportFixture()
        try fixture.expense("6.50", category: .parkingAndTolls, hoursAfterStart: 12)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .allHistory, exportedAt: ExportFixture.start)

        #expect(document.expenses.first?.note == nil)
        #expect(try text(document).contains("\"note\" : null"))
    }

    @Test("A file with expenses decodes back into itself")
    func roundTrips() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", category: .fuel, hoursAfterStart: 9.5, note: "Half tank")
        try fixture.expense("6.50", category: .parkingAndTolls, hoursAfterStart: 12)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let decoded = try encoder.document(from: try encoder.json(for: document))

        #expect(decoded == document)
        #expect(decoded.expenses == document.expenses)
        #expect(decoded.summary?.expenses == document.summary?.expenses)
    }

    // MARK: The format version

    @Test("Adding expenses was additive, so the format version is still 2")
    func versionDidNotMove() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let object = try object(document)

        #expect(ExportFormat.version == 2)
        #expect(object["formatVersion"] as? Int == 2)

        // The version-2 top-level keys are all still there and still mean what
        // they meant: `expenses` was added beside them, and nothing was renamed,
        // removed or redefined. That is the whole reason the number did not move.
        let versionTwoKeys: Set<String> = [
            "formatVersion", "producer", "exportedAt", "scope", "shiftCount", "shifts", "summary"
        ]
        #expect(versionTwoKeys.isSubset(of: Set(object.keys)))
        #expect(Set(object.keys).subtracting(versionTwoKeys) == ["expenses"])

        // `shiftCount` still counts shifts, and not records of any other kind.
        #expect(object["shiftCount"] as? Int == 1)

        // The scope vocabulary is the same closed set version 2 documented.
        let scope = try #require(object["scope"] as? [String: Any])
        #expect(scope["kind"] as? String == "day")
        #expect(Set(scope.keys) == ["kind", "periodStart", "periodEndExclusive"])
    }

    @Test("The summary gained two blocks and changed none of the ones it had")
    func summaryKeysAreAdditive() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let object = try object(document)
        let summary = try #require(object["summary"] as? [String: Any])

        let versionTwoKeys: Set<String> = [
            "completedShiftCount", "elapsed", "deliveryActive", "nonDelivery", "earnings",
            "deliveryEarnings", "route", "deliveries",
            "grossPerElapsedHour", "grossPerDeliveryActiveHour", "grossPerRecordedMile"
        ]
        #expect(versionTwoKeys.isSubset(of: Set(summary.keys)))
        #expect(Set(summary.keys).subtracting(versionTwoKeys) == ["expenses", "netAfterRecordedExpenses"])

        // The earnings block is untouched: the net is a new field beside it, not
        // a redefinition of the figure a version-2 reader already reads.
        let earnings = try #require(summary["earnings"] as? [String: Any])
        #expect(earnings["recordedGrossEarnings"] as? String == "86.25")
        #expect(
            Set(earnings.keys) == [
                "recordedGrossEarnings", "contributingShiftCount", "totalShiftCount", "currencyCode"
            ]
        )
    }

    // MARK: CSV

    @Test("The CSV is unchanged: the same 32 delivery columns, and no expense in them")
    func csvIsUnchanged() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        try fixture.delivered(in: shift, acceptedAfter: 600)
        try fixture.expense("42.10", category: .fuel, hoursAfterStart: 9.5, note: "Half tank")
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .period(try day(fixture)), exportedAt: ExportFixture.start)
        let csv = String(decoding: try encoder.data(for: document, as: .csv), as: UTF8.self)
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }

        #expect(ExportDocumentEncoder.columns.count == 32)
        #expect(lines.count == 2, "A header and one delivery row: no second table was appended")
        #expect(lines.first?.contains("expense") == false)
        // The row shape a spreadsheet parses stays one shape all the way down.
        #expect(!csv.contains("42.10"))
        #expect(!csv.contains("Half tank"))
    }

    @Test("The format picker says the CSV leaves expenses out, and why")
    func csvExplanationSaysSo() {
        let explanation = ExportFileFormat.csv.explanation.lowercased()

        #expect(explanation.contains("expense"))
        #expect(explanation.contains("date"), "And says an expense belongs to a date rather than to a delivery")
        #expect(ExportFileFormat.json.explanation.lowercased().contains("expense"))
    }

    // MARK: Privacy

    @Test("A note leaves only in an export the driver started, and nothing else does")
    func privacy() throws {
        let fixture = try ExportFixture()
        try fixture.expense("42.10", category: .fuel, hoursAfterStart: 9.5, note: "Half tank")
        try fixture.context.save()

        let document = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar)
            .document(for: .allHistory, exportedAt: ExportFixture.start)
        let text = try text(document)

        // The note is the driver's own record and is exported, like a pickup
        // place name. What must not appear is anything the app derived about
        // them alongside it.
        #expect(text.contains("Half tank"))
        for absent in ["latitude", "longitude", "coordinate", "normalizedName", "deviceName", "timeZone"] {
            #expect(!text.contains(absent), "\(absent) must not be in an export")
        }
    }

    @Test("The file the driver shares says how many expenses are in it")
    func fileStatesItsExpenses() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(earnings: "86.25")
        try fixture.expense("42.10", hoursAfterStart: 9.5)
        try fixture.expense("6.50", category: .parkingAndTolls, hoursAfterStart: 12)
        try fixture.context.save()

        let directory = URL.temporaryDirectory.appending(path: "DashPilotExpenseExport-\(UUID().uuidString)")
        let store = ExportFileStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar, files: store)
            .export(.period(try day(fixture)), as: .json, exportedAt: ExportFixture.start)

        #expect(file.shiftCount == 1)
        #expect(file.expenseCount == 2)
        #expect(file.sizeStatement(locale: Locale(identifier: "en_US")).hasPrefix("1 shift · 2 expenses · "))
    }

    @Test("A file of costs alone does not claim to hold shifts")
    func expenseOnlyFileStatement() throws {
        let file = ExportedFile(
            url: URL(fileURLWithPath: "/dev/null"),
            fileName: "DashPilot-Day-2026-06-17.json",
            format: .json,
            byteCount: 1_024,
            shiftCount: 0,
            expenseCount: 1
        )

        #expect(file.sizeStatement(locale: Locale(identifier: "en_US")).hasPrefix("1 expense · "))
        #expect(!file.sizeStatement().contains("0 shifts"))
    }
}
