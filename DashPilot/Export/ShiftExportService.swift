import Foundation
import OSLog
import SwiftData

/// Produces an export file from what the store holds.
///
/// ## The seam
///
/// This is the **only** part of the export layer that touches SwiftData. It
/// fetches the shifts a scope names, measures their routes, and hands plain
/// values to ``ShiftExportRecord`` and ``ExportDocumentEncoder``, neither of
/// which knows the store exists. That is what lets the file contract be
/// asserted, byte for byte, without a container.
///
/// ## Only ever history, and only when asked
///
/// Nothing here runs on its own. There is no scheduled export, no export on
/// shift end and no export at launch: a file is written because the driver
/// tapped a control, and it is written to a temporary location on the device.
/// No network call exists anywhere in DashPilot, so there is nowhere for one to
/// be sent.
///
/// A running shift is refused rather than exported half-finished — the model
/// adapter enforces that, so the rule holds whatever a scope or a screen asks
/// for.
///
/// ## `@MainActor`
///
/// Like the other services: every operation runs to completion without
/// suspending, over the same context the views read.
@MainActor
struct ShiftExportService {
    private let context: ModelContext
    private let calendar: Calendar
    private let files: ExportFileStore
    private let encoder = ExportDocumentEncoder()
    private let periodCalculator = PeriodMetricsCalculator()

    init(
        context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        files: ExportFileStore = ExportFileStore()
    ) {
        self.context = context
        self.calendar = calendar
        self.files = files
    }

    /// Builds the file and returns where it was written.
    ///
    /// - Throws: ``ShiftExportError``.
    func export(
        _ scope: ExportScope,
        as format: ExportFileFormat,
        exportedAt: Date = .now
    ) throws -> ExportedFile {
        let document = try document(for: scope, exportedAt: exportedAt)
        let data = try encoder.data(for: document, as: format)
        let file = try files.write(
            data,
            named: ExportFileStore.fileName(
                for: scope,
                format: format,
                date: fileNameDate(for: scope, document: document, exportedAt: exportedAt),
                calendar: calendar
            ),
            format: format,
            shiftCount: document.shiftCount
        )
        // The scope's kind and the format, and a count. Never a date a driver
        // worked, never an amount, never a place, and never the path the file
        // was written to.
        AppLog.export.info(
            """
            Export written: scope \(scope.kind, privacy: .public), \
            format \(format.rawValue, privacy: .public), \
            \(document.shiftCount, privacy: .public) shifts
            """
        )
        return file
    }

    /// The document a scope produces, before it becomes bytes.
    ///
    /// Separated from ``export(_:as:exportedAt:)`` so the contract can be
    /// asserted without writing a file.
    ///
    /// - Throws: ``ShiftExportError``.
    func document(for scope: ExportScope, exportedAt: Date = .now) throws -> ExportDocument {
        let shifts = try shifts(in: scope)
        guard !shifts.isEmpty else {
            AppLog.export.notice("Export refused: no completed shifts in scope \(scope.kind, privacy: .public)")
            throw ShiftExportError.noCompletedShiftsInScope
        }

        // Measured once per shift and reused for the shift's own record and for
        // the period summary, because measuring walks every position a shift
        // holds and a week can hold several shifts' worth.
        let distances = shifts.reduce(into: [UUID: RouteDistance]()) { distances, shift in
            distances[shift.id] = shift.recordedDistance()
        }

        let records = try shifts.map { shift in
            try shift.exportRecord(for: distances[shift.id] ?? .none)
        }

        return ExportDocument(
            scope: scope,
            shifts: records,
            summary: summary(for: scope, shifts: shifts, distances: distances),
            exportedAt: exportedAt
        )
    }

    /// Empties the temporary export directory.
    ///
    /// Called at launch so a file left behind by a terminated share does not
    /// outlive the session that made it. See ``ExportFileStore``.
    func purgeTemporaryExports() {
        files.purge()
    }

    // MARK: Reading the store

    /// The completed shifts a scope covers, newest first.
    ///
    /// Newest first everywhere, matching the order history is read in, so the
    /// file and the screen agree about what "the first shift" is.
    private func shifts(in scope: ExportScope) throws -> [Shift] {
        switch scope {
        case let .shift(id):
            let shift = try fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id }))
            guard let shift = shift.first else { throw ShiftExportError.shiftUnavailable }
            // Checked here as well as in the record adapter: a scope naming a
            // running shift is a mistake worth reporting as itself rather than
            // as an empty document.
            guard !shift.isActive else { throw ShiftExportError.shiftNotCompleted }
            return [shift]

        case let .period(period):
            let start = period.start
            let end = period.end
            return try fetch(
                FetchDescriptor<Shift>(
                    // The same membership rule the period summary applies: a
                    // shift belongs to the period containing its start, and a
                    // half-open span puts a midnight start in exactly one.
                    predicate: #Predicate {
                        $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end
                    },
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
            )

        case .allHistory:
            return try fetch(
                FetchDescriptor<Shift>(
                    predicate: #Predicate { $0.endedAt != nil },
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
            )
        }
    }

    private func fetch(_ descriptor: FetchDescriptor<Shift>) throws -> [Shift] {
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.export.error("Failed to read shifts for export: \(error)")
            throw ShiftExportError.storeUnavailable
        }
    }

    // MARK: The period summary

    /// The period's figures, or `nil` for a scope that is not a calendar span.
    ///
    /// Derived through ``PeriodMetricsCalculator`` rather than re-summed here,
    /// so a file and the summary screen it was exported from cannot disagree
    /// about a single figure or a single coverage count.
    private func summary(
        for scope: ExportScope,
        shifts: [Shift],
        distances: [UUID: RouteDistance]
    ) -> PeriodExportSummary? {
        guard let period = scope.period else { return nil }
        let records = shifts.map { $0.periodRecord(for: distances[$0.id] ?? .none) }
        return PeriodExportSummary(periodCalculator.metrics(of: records, in: period))
    }

    // MARK: Naming

    /// The day a file's name is built from: the day the records are about.
    ///
    /// A single shift is named for the day it started, a period for the day the
    /// period began, and an all-history export for the day it was written —
    /// which is the only date that describes it.
    private func fileNameDate(for scope: ExportScope, document: ExportDocument, exportedAt: Date) -> Date {
        switch scope {
        case .shift: document.shifts.first?.startedAt ?? exportedAt
        case let .period(period): period.start
        case .allHistory: exportedAt
        }
    }
}
