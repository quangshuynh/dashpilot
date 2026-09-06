import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// Choosing what to export, and writing it.
///
/// The service is the only part of the export layer that touches the store, so
/// these are the tests about *scope* — which shifts a request selects, which it
/// refuses — and about the file that comes out of it.
@Suite("Shift export service")
@MainActor
struct ShiftExportServiceTests {
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

    // MARK: Scope

    @Test("A single-shift scope exports that shift and nothing else")
    func singleShiftScope() throws {
        let fixture = try ExportFixture()
        let subject = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        try fixture.completedShift(startedAfter: 14, earnings: "40.00")

        let document = try service(fixture, files: store())
            .document(for: .shift(subject.id), exportedAt: ExportFixture.start)

        #expect(document.shiftCount == 1)
        #expect(document.shifts.first?.id == subject.id)
        #expect(document.summary == nil)
    }

    @Test("A running shift cannot be exported as history")
    func runningShiftRefused() throws {
        let fixture = try ExportFixture()
        let running = fixture.runningShift()

        #expect(throws: ShiftExportError.shiftNotCompleted) {
            try service(fixture, files: store()).document(for: .shift(running.id))
        }
    }

    @Test("A shift that is no longer in the store is reported as gone")
    func missingShift() throws {
        let fixture = try ExportFixture()

        #expect(throws: ShiftExportError.shiftUnavailable) {
            try service(fixture, files: store()).document(for: .shift(UUID()))
        }
    }

    @Test("A period exports the completed shifts that started in it, and no others")
    func periodScope() throws {
        let fixture = try ExportFixture()
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )

        try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        try fixture.completedShift(startedAfter: 14)
        // The next day, and a running one today: neither belongs.
        try fixture.completedShift(startedAfter: 30)
        fixture.runningShift(startedAfter: 20)

        let document = try service(fixture, files: store())
            .document(for: .period(period), exportedAt: ExportFixture.start)

        #expect(document.shiftCount == 2)
        #expect(document.summary?.completedShiftCount == 2)
    }

    @Test("A shift running past midnight is exported whole, on the day it began")
    func overnightShift() throws {
        let fixture = try ExportFixture()
        // 22:00 to 02:00 the next day.
        try fixture.completedShift(startedAfter: 22, lasting: 4, earnings: "90.00")

        let first = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let second = try #require(first.next(using: ExportFixture.calendar))
        let service = service(fixture, files: store())

        #expect(try service.document(for: .period(first)).shiftCount == 1)
        // Not split, and not counted again in the day it ended.
        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try service.document(for: .period(second))
        }
    }

    @Test("All history exports every completed shift, newest first, and never a running one")
    func allHistoryScope() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        try fixture.completedShift(startedAfter: 14)
        try fixture.completedShift(startedAfter: 30)
        fixture.runningShift(startedAfter: 40)

        let document = try service(fixture, files: store()).document(for: .allHistory)

        #expect(document.shiftCount == 3)
        #expect(document.shifts.map(\.startedAt) == document.shifts.map(\.startedAt).sorted(by: >))
        #expect(document.summary == nil)
    }

    @Test("An empty scope is refused rather than producing a file with nothing in it")
    func emptyScope() throws {
        let fixture = try ExportFixture()

        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try service(fixture, files: store()).document(for: .allHistory)
        }
    }

    @Test("A period with only a running shift in it is empty")
    func periodWithOnlyARunningShift() throws {
        let fixture = try ExportFixture()
        fixture.runningShift(startedAfter: 9)
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )

        #expect(throws: ShiftExportError.noCompletedShiftsInScope) {
            try service(fixture, files: store()).document(for: .period(period))
        }
    }

    // MARK: The summary

    @Test("A period summary agrees with the calculator the screen reads")
    func summaryAgreesWithTheCalculator() throws {
        let fixture = try ExportFixture()
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let paid = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "90.00")
        fixture.attachRoute(to: paid, sessions: 1)
        try fixture.completedShift(startedAfter: 14, lasting: 2)

        let document = try service(fixture, files: store()).document(for: .period(period))
        let summary = try #require(document.summary)

        let records = [paid, try #require(try fixture.context.fetch(
            FetchDescriptor<Shift>(predicate: #Predicate { $0.endedAt != nil })
        ).first { $0.id != paid.id })]
        let expected = PeriodExportSummary(
            PeriodMetricsCalculator().metrics(
                of: records.map { $0.periodRecord(for: $0.recordedDistance()) },
                in: period
            )
        )

        #expect(summary == expected)
    }

    // MARK: Writing

    @Test("A JSON export writes a non-empty file with the expected name and extension")
    func writesJSON() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        let files = store()
        defer { files.purge() }

        let file = try service(fixture, files: files)
            .export(.shift(shift.id), as: .json, exportedAt: ExportFixture.start)

        #expect(file.fileName == "DashPilot-Shift-2026-06-17.json")
        #expect(file.format == .json)
        #expect(file.shiftCount == 1)
        #expect(file.byteCount > 0)
        #expect(file.url.pathExtension == "json")
        // Inside DashPilot's own temporary export directory, not anywhere the
        // driver's other data lives.
        #expect(file.url.deletingLastPathComponent() == files.directory)

        let written = try Data(contentsOf: file.url)
        #expect(written.count == file.byteCount)
        #expect(String(decoding: written, as: UTF8.self).contains("\"formatVersion\" : 2"))
    }

    @Test("A CSV export writes a non-empty file with the expected name and extension")
    func writesCSV() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9)
        let files = store()
        defer { files.purge() }

        let file = try service(fixture, files: files)
            .export(.shift(shift.id), as: .csv, exportedAt: ExportFixture.start)

        #expect(file.fileName == "DashPilot-Shift-2026-06-17.csv")
        #expect(file.url.pathExtension == "csv")
        let written = String(decoding: try Data(contentsOf: file.url), as: UTF8.self)
        #expect(written.hasPrefix("shiftStartedAt,"))
    }

    @Test("A period file is named for the period, and history for the day it was written")
    func fileNames() throws {
        let fixture = try ExportFixture()
        try fixture.completedShift(startedAfter: 9)
        let files = store()
        defer { files.purge() }
        let service = service(fixture, files: files)

        let day = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let week = try #require(
            ReportingPeriod(unit: .week, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )

        #expect(
            try service.export(.period(day), as: .json, exportedAt: ExportFixture.start).fileName
                == "DashPilot-Day-2026-06-17.json"
        )
        // 17 June 2026 is a Wednesday, and this calendar's week starts on
        // Sunday, so the week began on the 14th.
        #expect(
            try service.export(.period(week), as: .csv, exportedAt: ExportFixture.start).fileName
                == "DashPilot-Week-2026-06-14.csv"
        )
        #expect(
            try service.export(.allHistory, as: .json, exportedAt: ExportFixture.start).fileName
                == "DashPilot-History-2026-06-17.json"
        )
    }

    @Test("A file name carries no pickup place, amount or other content")
    func fileNamesCarryNoContent() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, earnings: "86.25")
        try fixture.delivered(in: shift, acceptedAfter: 300, place: try fixture.place(named: "Nowhere Noodles"))
        let files = store()
        defer { files.purge() }

        let name = try service(fixture, files: files)
            .export(.shift(shift.id), as: .json, exportedAt: ExportFixture.start).fileName

        #expect(!name.localizedCaseInsensitiveContains("noodles"))
        #expect(!name.contains("86"))
        // Filesystem-safe: ASCII letters, digits, hyphens and one full stop.
        #expect(name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
    }

    @Test("Exporting twice replaces the file rather than accumulating copies")
    func exportsDoNotAccumulate() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9)
        let files = store()
        defer { files.purge() }
        let service = service(fixture, files: files)

        _ = try service.export(.shift(shift.id), as: .json, exportedAt: ExportFixture.start)
        _ = try service.export(.shift(shift.id), as: .csv, exportedAt: ExportFixture.start)
        let last = try service.export(.shift(shift.id), as: .json, exportedAt: ExportFixture.start)

        let contents = try FileManager.default.contentsOfDirectory(
            at: files.directory,
            includingPropertiesForKeys: nil
        )
        #expect(contents.map(\.lastPathComponent) == [last.fileName])
    }

    @Test("A file the export did not write is never overwritten")
    func neverOverwritesAnUnrelatedFile() throws {
        let files = store()
        defer { files.purge() }

        // Something already at the name the export would use. Unreachable in an
        // ordinary run — the purge clears the directory first — which is why the
        // guard is asserted directly rather than through a write.
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let occupied = files.directory.appendingPathComponent("DashPilot-Shift-2026-06-17.json")
        try Data("not an export".utf8).write(to: occupied)

        let next = files.availableURL(for: "DashPilot-Shift-2026-06-17.json")

        #expect(next.lastPathComponent == "DashPilot-Shift-2026-06-17-2.json")
        #expect(String(decoding: try Data(contentsOf: occupied), as: UTF8.self) == "not an export")
    }

    @Test("Purging empties the export directory and tolerates one that is not there")
    func purge() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9)
        let files = store()

        let file = try service(fixture, files: files)
            .export(.shift(shift.id), as: .json, exportedAt: ExportFixture.start)
        #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))

        files.purge()
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: files.directory.path(percentEncoded: false)))

        // Purging again is not an error.
        files.purge()
    }

    @Test("A write into a location that cannot be created is surfaced cleanly")
    func writeFailureIsSurfaced() throws {
        // A directory cannot be created underneath a regular file, which is the
        // simplest way to reach the failure without stubbing FileManager.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashPilotExportBlocker-\(UUID().uuidString)")
        try Data("blocked".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let files = ExportFileStore(directory: blocker.appendingPathComponent("Exports", isDirectory: true))

        #expect(throws: ShiftExportError.temporaryLocationUnavailable) {
            try files.write(Data("{}".utf8), named: "DashPilot-Shift-2026-06-17.json", format: .json, shiftCount: 1)
        }
    }

    // MARK: What the file says about itself

    @Test("The size statement counts shifts rather than describing them")
    func sizeStatement() {
        let file = ExportedFile(
            url: URL(filePath: "/tmp/DashPilot-Week-2026-06-14.json"),
            fileName: "DashPilot-Week-2026-06-14.json",
            format: .json,
            byteCount: 4_096,
            shiftCount: 3,
            expenseCount: 0
        )

        #expect(file.sizeStatement(locale: Locale(identifier: "en_US")).hasPrefix("3 shifts · "))
        #expect(
            ExportedFile(
                url: file.url,
                fileName: file.fileName,
                format: .json,
                byteCount: 1_024,
                shiftCount: 1,
                expenseCount: 0
            )
            .sizeStatement(locale: Locale(identifier: "en_US"))
            .hasPrefix("1 shift · ")
        )
    }

    @Test("Every export error explains itself without naming a path")
    func errorsAreReadable() {
        let errors: [ShiftExportError] = [
            .noCompletedShiftsInScope, .shiftNotCompleted, .shiftUnavailable,
            .storeUnavailable, .encodingFailed, .temporaryLocationUnavailable, .writeFailed
        ]
        for error in errors {
            let message = error.errorDescription
            #expect(message?.isEmpty == false)
            #expect(message?.contains("/") == false, "an error must not expose a path")
            #expect(message?.localizedCaseInsensitiveContains("tmp") == false)
        }
    }
}
