import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Exporting a calendar month and a chosen date range.
///
/// The rules these assert are the export layer's existing ones — membership by
/// `startedAt`, a running shift refused, an empty scope refused, no coordinates,
/// missing staying missing. They are asserted again for the two new scopes
/// because the scope is what decides which records reach the file, and a new
/// scope is exactly where a second set of selection rules could appear.
@Suite("Month and range export")
@MainActor
struct MonthAndRangeExportTests {
    /// A throwaway export directory per test, so nothing here can write into
    /// the app's own temporary location or into another test's.
    private func store() -> ExportFileStore {
        ExportFileStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("DashPilotExportTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func service(_ fixture: ExportFixture, files: ExportFileStore) -> ShiftExportService {
        ShiftExportService(context: fixture.context, calendar: ExportFixture.calendar, files: files)
    }

    /// June 2026, in the fixture's UTC calendar. `ExportFixture.start` is
    /// midnight on Wednesday 17 June 2026.
    private func june() throws -> ReportingPeriod {
        try #require(ReportingPeriod(unit: .month, containing: ExportFixture.start, calendar: ExportFixture.calendar))
    }

    private func range(fromHours: Double, throughHours: Double, _ fixture: ExportFixture) throws -> ReportingPeriod {
        try #require(
            ReportingPeriod(
                from: fixture.at(fromHours),
                through: fixture.at(throughHours),
                calendar: ExportFixture.calendar
            )
        )
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Scope

    @Test("A month exports the completed shifts that started in it, and no others")
    func monthScope() throws {
        let fixture = try ExportFixture()
        let inside = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        // 29 June: still June. 30 June is the last day the month holds.
        let alsoInside = try fixture.completedShift(startedAfter: 12 * 24 + 9, earnings: "40.00")
        // 3 July: outside it.
        let nextMonth = try fixture.completedShift(startedAfter: 16 * 24 + 9)

        let document = try service(fixture, files: store())
            .document(for: .period(try june()), exportedAt: ExportFixture.start)

        #expect(document.shiftCount == 2)
        #expect(Set(document.shifts.map(\.id)) == [inside.id, alsoInside.id])
        #expect(!document.shifts.map(\.id).contains(nextMonth.id))
        #expect(document.summary != nil)
    }

    @Test("A chosen range exports the completed shifts that started in it")
    func rangeScope() throws {
        let fixture = try ExportFixture()
        let inside = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        let alsoInside = try fixture.completedShift(startedAfter: 2 * 24 + 9, earnings: "40.00")
        let after = try fixture.completedShift(startedAfter: 4 * 24 + 9)

        // 17 June through 19 June, inclusive.
        let period = try range(fromHours: 0, throughHours: 2 * 24 + 12, fixture)
        let document = try service(fixture, files: store())
            .document(for: .period(period), exportedAt: ExportFixture.start)

        #expect(document.shiftCount == 2)
        #expect(Set(document.shifts.map(\.id)) == [inside.id, alsoInside.id])
        #expect(!document.shifts.map(\.id).contains(after.id))
    }

    /// The half-open rule, at the one boundary a driver picking inclusive dates
    /// would most plausibly get wrong.
    @Test("A shift starting on the day after a range's last day is outside it")
    func rangeExcludesTheDayAfterItsLastDate() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        // Midnight exactly, on the day after the selected end.
        let justAfter = try fixture.completedShift(startedAfter: 3 * 24)

        // 17 June through 19 June.
        let period = try range(fromHours: 0, throughHours: 2 * 24 + 12, fixture)
        let document = try service(fixture, files: store())
            .document(for: .period(period), exportedAt: ExportFixture.start)

        #expect(document.shiftCount == 1)
        #expect(!document.shifts.map(\.id).contains(justAfter.id))
    }

    @Test("A shift crossing into the next month exports whole, in the month it began")
    func overnightShiftExportsWholeInItsStartMonth() throws {
        let fixture = try ExportFixture()
        // Starts 30 June at 23:00 UTC and ends 1 July at 02:00.
        let shift = Shift(startedAt: fixture.at(13 * 24 + 23))
        try shift.end(at: fixture.at(14 * 24 + 2))
        try shift.setGrossEarnings(try fixture.money("75.00"))
        fixture.context.insert(shift)

        let july = try #require(
            ReportingPeriod(unit: .month, containing: fixture.at(20 * 24), calendar: ExportFixture.calendar)
        )
        let exporter = service(fixture, files: store())

        let inJune = try exporter.document(for: .period(try june()), exportedAt: ExportFixture.start)
        #expect(inJune.shiftCount == 1)
        #expect(inJune.shifts.first?.id == shift.id)
        // Nothing is split at the boundary: the whole three hours are June's.
        #expect(inJune.shifts.first?.elapsedSeconds == 3 * 3600)

        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try exporter.document(for: .period(july))
        }
    }

    @Test("A running shift is not exported by a month or a range containing it")
    func runningShiftIsNeverInAPeriodExport() throws {
        let fixture = try ExportFixture()
        let completed = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        let running = fixture.runningShift(startedAfter: 20)
        let exporter = service(fixture, files: store())

        let month = try exporter.document(for: .period(try june()), exportedAt: ExportFixture.start)
        let chosen = try exporter.document(
            for: .period(try range(fromHours: 0, throughHours: 12, fixture)),
            exportedAt: ExportFixture.start
        )

        #expect(month.shifts.map(\.id) == [completed.id])
        #expect(chosen.shifts.map(\.id) == [completed.id])
        #expect(!month.shifts.map(\.id).contains(running.id))
    }

    @Test("An empty month and an empty range are refused rather than written empty")
    func emptyScopesAreRefused() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        let exporter = service(fixture, files: store())

        // A month with nothing in it: 6 months before the fixture's own.
        let quietMonth = try #require(
            ReportingPeriod(
                unit: .month,
                containing: fixture.at(-180 * 24),
                calendar: ExportFixture.calendar
            )
        )
        let quietRange = try range(fromHours: -10 * 24, throughHours: -8 * 24, fixture)

        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try exporter.document(for: .period(quietMonth))
        }
        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try exporter.document(for: .period(quietRange))
        }
    }

    // MARK: File names

    @Test("A month is named by its month and a range by both of its days")
    func fileNames() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        let files = store()
        defer { files.purge() }
        let exporter = service(fixture, files: files)

        #expect(
            try exporter.export(.period(try june()), as: .json, exportedAt: ExportFixture.start).fileName
                == "DashPilot-Month-2026-06.json"
        )
        // 17 June through 24 June, inclusive: the name ends on the 24th, not on
        // the exclusive boundary that follows it.
        #expect(
            try exporter.export(
                .period(try range(fromHours: 0, throughHours: 7 * 24 + 12, fixture)),
                as: .csv,
                exportedAt: ExportFixture.start
            ).fileName == "DashPilot-Range-2026-06-17-to-2026-06-24.csv"
        )
    }

    @Test("A one-day range names the same day twice rather than reaching past it")
    func oneDayRangeFileName() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        let files = store()
        defer { files.purge() }

        let name = try service(fixture, files: files).export(
            .period(try range(fromHours: 1, throughHours: 20, fixture)),
            as: .json,
            exportedAt: ExportFixture.start
        ).fileName

        #expect(name == "DashPilot-Range-2026-06-17-to-2026-06-17.json")
    }

    @Test("The new file names stay filesystem-safe and carry no content")
    func fileNamesAreSafe() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        try fixture.delivered(in: shift, acceptedAfter: 300, place: try fixture.place(named: "Nowhere Noodles"))
        let files = store()
        defer { files.purge() }
        let exporter = service(fixture, files: files)

        for scope in [ExportScope.period(try june()), .period(try range(fromHours: 0, throughHours: 48, fixture))] {
            let name = try exporter.export(scope, as: .json, exportedAt: ExportFixture.start).fileName
            #expect(!name.localizedCaseInsensitiveContains("noodles"))
            #expect(!name.contains("86"))
            #expect(!name.contains("/"), "A file name never carries a locale-formatted date: \(name)")
            #expect(name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
        }
    }

    // MARK: The file contract

    @Test("A month scope names itself and carries its half-open span")
    func monthScopeMetadata() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)

        let document = try service(fixture, files: store())
            .document(for: .period(try june()), exportedAt: ExportFixture.start)
        let scope = try #require(try object(try ExportDocumentEncoder().json(for: document))["scope"] as? [String: Any])

        #expect(scope["kind"] as? String == "month")
        #expect(scope["periodStart"] as? String == "2026-06-01T00:00:00Z")
        #expect(scope["periodEndExclusive"] as? String == "2026-07-01T00:00:00Z")
    }

    /// The one place the inclusive interface and the half-open domain could be
    /// read as disagreeing, so the file says which it means in the key itself.
    @Test("A range scope writes the exclusive end, and the key says so")
    func rangeScopeMetadata() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)

        // The driver chose 17 June through 19 June.
        let period = try range(fromHours: 0, throughHours: 2 * 24 + 12, fixture)
        let document = try service(fixture, files: store())
            .document(for: .period(period), exportedAt: ExportFixture.start)
        let scope = try #require(try object(try ExportDocumentEncoder().json(for: document))["scope"] as? [String: Any])

        #expect(scope["kind"] as? String == "custom")
        #expect(scope["periodStart"] as? String == "2026-06-17T00:00:00Z")
        // The day *after* the last one selected. Named `Exclusive` for exactly
        // this reason.
        #expect(scope["periodEndExclusive"] as? String == "2026-06-20T00:00:00Z")
        #expect(scope["periodEnd"] == nil, "The version-1 key is gone, not kept alongside")
    }

    @Test("A month and a range carry the same period summary the screen shows")
    func periodSummaryIsCarried() throws {
        let fixture = try ExportFixture()
        let first = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        fixture.attachRoute(to: first, sessions: 2)
        try fixture.completedShift(startedAfter: 5 * 24 + 9)

        let document = try service(fixture, files: store())
            .document(for: .period(try june()), exportedAt: ExportFixture.start)
        let summary = try #require(document.summary)

        #expect(summary.completedShiftCount == 2)
        // The coverage pair survives the larger period: one of two shifts has an
        // amount, and the file says so rather than reporting a total.
        #expect(summary.earnings.contributingShiftCount == 1)
        #expect(summary.earnings.totalShiftCount == 2)
    }

    @Test("A CSV of a month holds the month's records and no extra columns")
    func csvIsUnchangedByTheScope() throws {
        let fixture = try ExportFixture()
        let first = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        try fixture.delivered(in: first, acceptedAfter: 300, place: try fixture.place(named: "Nowhere Noodles"))
        try fixture.completedShift(startedAfter: 5 * 24 + 9)
        try fixture.completedShift(startedAfter: 40 * 24 + 9)

        let encoder = ExportDocumentEncoder()
        let exporter = service(fixture, files: store())
        let month = try encoder.csv(
            for: try exporter.document(for: .period(try june()), exportedAt: ExportFixture.start)
        )
        let day = try encoder.csv(
            for: try exporter.document(
                for: .period(
                    try #require(
                        ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
                    )
                ),
                exportedAt: ExportFixture.start
            )
        )

        let monthText = String(decoding: month, as: UTF8.self)
        let dayText = String(decoding: day, as: UTF8.self)
        let header = try #require(monthText.split(separator: "\r\n", omittingEmptySubsequences: false).first)

        // The same header for every scope: a longer period is more rows, never
        // more columns.
        #expect(dayText.hasPrefix(String(header)))
        #expect(monthText.split(separator: "\r\n", omittingEmptySubsequences: false).count
            > dayText.split(separator: "\r\n", omittingEmptySubsequences: false).count)
        // Still no second table, and still no coverage pair flattened into a cell.
        #expect(!monthText.contains("contributing"))
    }

    /// The privacy rule does not soften because a scope is larger. A month of
    /// routes is more positions, not more permission to write them out.
    @Test("A month export still carries no coordinate")
    func monthExportHasNoCoordinates() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        fixture.attachRoute(to: shift, sessions: 2)

        let document = try service(fixture, files: store())
            .document(for: .period(try june()), exportedAt: ExportFixture.start)
        let json = String(decoding: try ExportDocumentEncoder().json(for: document), as: UTF8.self)

        for field in ["latitude", "longitude", "coordinate", "routeSample"] {
            #expect(!json.localizedCaseInsensitiveContains(field), "\(field) must not appear in an export")
        }
        let samples = try fixture.context.fetch(FetchDescriptor<RouteSample>())
        #expect(!samples.isEmpty, "the fixture must actually hold positions for this to prove anything")
        for sample in samples {
            for rendering in [String(sample.latitude), String(format: "%.5f", sample.latitude)]
            where rendering.count >= 8 {
                #expect(!json.contains(rendering))
            }
        }
    }
}

/// The decision to move the export contract to version 2, written down as
/// assertions.
///
/// The store's schema is unrelated and unchanged at v7. What changed is the
/// **file**, and it changed in two ways a version-1 reader can be broken by, so
/// the number moved. See ``ExportFormat``.
@Suite("Export format version 2")
@MainActor
struct ExportFormatVersionTests {
    private func service(_ fixture: ExportFixture) -> ShiftExportService {
        ShiftExportService(
            context: fixture.context,
            calendar: ExportFixture.calendar,
            files: ExportFileStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("DashPilotExportTests-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    @Test("Every new document states version 2")
    func newDocumentsAreVersionTwo() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9)

        let document = try service(fixture).document(for: .shift(shift.id), exportedAt: ExportFixture.start)

        #expect(document.formatVersion == 2)
        #expect(ExportFormat.version == 2)
        // The file version and the store's schema version are different numbers
        // describing different things, and must never be assumed equal.
        #expect(ExportFormat.version != DashPilotSchemaV7.versionIdentifier.major)
    }

    /// Reason one for the bump: `scope.kind` can now say two things version 1
    /// never documented. A reader switching exhaustively over the old four
    /// values meets a fifth.
    @Test("The scope discriminator now carries values a version-1 reader never saw")
    func scopeKindGainedValues() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        let exporter = service(fixture)

        let month = try #require(
            ReportingPeriod(unit: .month, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let custom = try #require(
            ReportingPeriod(from: ExportFixture.start, through: ExportFixture.start, calendar: ExportFixture.calendar)
        )

        let versionOneKinds: Set<String> = ["shift", "day", "week", "allHistory"]
        let monthKind = try exporter.document(for: .period(month), exportedAt: ExportFixture.start).scope.kind
        let customKind = try exporter.document(for: .period(custom), exportedAt: ExportFixture.start).scope.kind

        #expect(monthKind == "month")
        #expect(customKind == "custom")
        #expect(!versionOneKinds.contains(monthKind))
        #expect(!versionOneKinds.contains(customKind))
    }

    /// Reason two: a key was **removed**, not added. `periodEnd` is gone and
    /// `periodEndExclusive` stands in its place, so a reader looking for the old
    /// name finds nothing rather than something subtly different.
    @Test("The renamed boundary key replaces the old one rather than joining it")
    func periodEndWasRenamedNotDuplicated() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        let week = try #require(
            ReportingPeriod(unit: .week, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )

        let document = try service(fixture).document(for: .period(week), exportedAt: ExportFixture.start)
        let json = try JSONSerialization.jsonObject(with: try ExportDocumentEncoder().json(for: document))
        let scope = try #require((json as? [String: Any])?["scope"] as? [String: Any])

        #expect(Set(scope.keys) == ["kind", "periodStart", "periodEndExclusive"])
    }

    /// Everything else about the contract is untouched by this interval. The
    /// bump is for the scope, not a licence to reshape the file.
    @Test("Version 2 keeps every other version-1 rule")
    func everythingElseIsUnchanged() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, earnings: "86.25")

        let document = try service(fixture).document(for: .shift(shift.id), exportedAt: ExportFixture.start)
        let data = try ExportDocumentEncoder().json(for: document)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["formatVersion", "producer", "exportedAt", "scope", "shiftCount", "shifts", "summary"])
        #expect(object["producer"] as? String == "DashPilot")
        // Money is still a decimal string, never a JSON number.
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"86.25\""))
        // A document still decodes back to itself.
        let decoded = try ExportDocumentEncoder().document(from: data)
        #expect(decoded == document)
    }
}
