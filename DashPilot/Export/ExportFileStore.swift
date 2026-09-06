import Foundation
import OSLog

/// A file DashPilot has written and is ready to hand to the share sheet.
nonisolated struct ExportedFile: Equatable, Sendable {
    /// Where the file is, inside DashPilot's own temporary export directory.
    ///
    /// Never shown to the driver: a path names locations on their device and
    /// tells them nothing they can act on. The interface shows ``fileName``.
    let url: URL

    let fileName: String
    let format: ExportFileFormat
    let byteCount: Int

    /// How many completed shifts the file holds, so the sheet can say what is
    /// about to be shared before it is shared.
    let shiftCount: Int

    /// How many recorded expenses it holds. Counted separately because they are
    /// separate records: an expense belongs to no shift, so it cannot be implied
    /// by the shift count.
    let expenseCount: Int
}

nonisolated extension ExportedFile {
    /// `"3 shifts · 4 KB"`, and `"3 shifts · 2 expenses · 4 KB"` when the file
    /// also carries costs, for the line under the file name.
    ///
    /// A kind of record with nothing in it is left out rather than written as
    /// `0`: a day whose only record is a tank of fuel reads as `"2 expenses"`,
    /// not as `"0 shifts · 2 expenses"`.
    func sizeStatement(locale: Locale = .autoupdatingCurrent) -> String {
        var parts: [String] = []
        if shiftCount > 0 || expenseCount == 0 {
            parts.append(shiftCount == 1 ? "1 shift" : "\(shiftCount) shifts")
        }
        if expenseCount > 0 {
            parts.append(expenseCount == 1 ? "1 expense" : "\(expenseCount) expenses")
        }
        parts.append(byteCount.formatted(.byteCount(style: .file).locale(locale)))
        return parts.joined(separator: " · ")
    }
}

/// Where an export file lives while the driver decides what to do with it.
///
/// ## Temporary, and only ever one
///
/// Exports go into one directory inside the app's temporary area, and the
/// directory is **emptied before each new export is written**. So at most one
/// export exists at a time and a driver who exports a week every week does not
/// accumulate a year of copies of their own history inside the app — which
/// would be a second, unmanaged store of exactly the data this project is
/// careful about, sitting somewhere they never see.
///
/// The purge also runs once at launch, which is what clears a file left behind
/// when the app was terminated mid-share.
///
/// ## Why not delete it the moment the sheet closes
///
/// Because that is not safe. The system share sheet may still be reading the
/// file after it has visually dismissed — a mail composer attaching it, another
/// app copying it in — and pulling the file out from under it produces a
/// truncated attachment rather than an error anyone sees. Emptying on the *next*
/// export, and at launch, gets the same result without racing anything, and iOS
/// reclaims the temporary directory on its own besides.
///
/// ## File names
///
/// `DashPilot-Shift-2026-09-05.json`, `DashPilot-Week-2026-08-31.csv`,
/// `DashPilot-Month-2026-09.json`, `DashPilot-Range-2026-09-01-to-2026-09-07.json`.
/// ASCII letters, digits and hyphens only, so the name survives every
/// filesystem, mail client and cloud drive it may pass through. The dates are
/// machine-written — `yyyy-MM-dd`, never a locale-formatted one with slashes in
/// it — and they are the days the records are *about*, in the driver's own
/// calendar, because that is what they will look for later rather than the
/// instant the file was written.
///
/// A custom range names **both** of its days, and names the last day the driver
/// selected rather than the exclusive end: a file called `…-to-2026-09-08` for a
/// range chosen as *September 1 through 7* would be a name that contradicts the
/// screen it came from.
///
/// **No pickup place, no merchant and no amount appears in a file name.** A
/// name is the part of an export that shows up in a share sheet, a notification
/// and a folder listing, often on someone else's screen.
///
/// Deliberately not `Sendable`: it holds a `FileManager`, which is not, and it
/// is only ever used from ``ShiftExportService``, which is `@MainActor`.
nonisolated struct ExportFileStore {
    /// The directory exports are written to. One level under the app's
    /// temporary directory so it can be emptied wholesale without touching
    /// anything else there.
    let directory: URL

    private let fileManager: FileManager

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory
            ?? fileManager.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    /// Empties the export directory.
    ///
    /// Only DashPilot's own export directory, and never a path handed in from
    /// anywhere but this type. It does not throw: a purge that fails leaves a
    /// stale temporary file, which is not a reason to refuse the driver an
    /// export or to interrupt a launch.
    func purge() {
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            AppLog.export.error("Could not empty the temporary export directory: \(error.localizedDescription)")
        }
    }

    /// Writes one export, replacing whatever the directory held.
    ///
    /// - Throws: ``ShiftExportError/temporaryLocationUnavailable`` or
    ///   ``ShiftExportError/writeFailed``.
    func write(
        _ data: Data,
        named fileName: String,
        format: ExportFileFormat,
        shiftCount: Int,
        expenseCount: Int = 0
    ) throws -> ExportedFile {
        purge()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            AppLog.export.error("Could not create the temporary export directory: \(error.localizedDescription)")
            throw ShiftExportError.temporaryLocationUnavailable
        }

        let url = availableURL(for: fileName)
        do {
            // `.atomic` so a failure part-way through leaves no half-written
            // file for the share sheet to pick up.
            try data.write(to: url, options: [.atomic])
        } catch {
            AppLog.export.error("Could not write the export file: \(error.localizedDescription)")
            throw ShiftExportError.writeFailed
        }

        return ExportedFile(
            url: url,
            fileName: url.lastPathComponent,
            format: format,
            byteCount: data.count,
            shiftCount: shiftCount,
            expenseCount: expenseCount
        )
    }

    /// The first free name, so an export never overwrites a file it did not
    /// write.
    ///
    /// The purge above normally leaves the directory empty and the first
    /// candidate free. This is the guard for the case where it did not: a
    /// numbered suffix is added rather than the existing file replaced, because
    /// this code must never be the reason something on a driver's device is
    /// destroyed.
    ///
    /// Internal rather than private so the rule can be asserted directly. The
    /// path it guards is unreachable through ``write(_:named:format:shiftCount:expenseCount:)``
    /// in an ordinary run, which is exactly why it needs a test of its own.
    func availableURL(for fileName: String) -> URL {
        let candidate = directory.appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for suffix in 2...99 {
            let next = directory
                .appendingPathComponent("\(base)-\(suffix)", isDirectory: false)
                .appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: next.path(percentEncoded: false)) { return next }
        }
        return candidate
    }
}

nonisolated extension ExportFileStore {
    /// The name for one export.
    ///
    /// - Parameters:
    ///   - scope: what the file covers, which decides the middle word.
    ///   - date: the day the records are about, written in `calendar`'s time
    ///     zone.
    static func fileName(
        for scope: ExportScope,
        format: ExportFileFormat,
        date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        "DashPilot-\(scopeWord(scope))-\(datePart(for: scope, date: date, calendar: calendar)).\(format.fileExtension)"
    }

    /// The one word in the middle of a file name. Capitalised literals rather
    /// than a localised title, so the name is the same on every device.
    private static func scopeWord(_ scope: ExportScope) -> String {
        switch scope {
        case .shift: "Shift"
        case let .period(period):
            switch period.unit {
            case .day: "Day"
            case .week: "Week"
            case .month: "Month"
            case .custom: "Range"
            }
        case .allHistory: "History"
        }
    }

    /// The date part of a file name.
    ///
    /// A month is named by its month rather than by its first day: `2026-09`
    /// reads as *September* and sorts beside every other month, where
    /// `2026-09-01` reads as a single day. A custom range names both of the days
    /// the driver chose. Everything else names the one day it is about.
    private static func datePart(for scope: ExportScope, date: Date, calendar: Calendar) -> String {
        guard case let .period(period) = scope else { return dayString(date, calendar: calendar) }
        switch period.unit {
        case .day, .week:
            return dayString(date, calendar: calendar)
        case .month:
            return string(period.start, format: "yyyy-MM", calendar: calendar)
        case .custom:
            // The last instant *inside* the range, so the name ends on the day
            // the driver selected rather than on the exclusive boundary after it.
            return "\(dayString(period.start, calendar: calendar))-to-\(dayString(period.lastInstant, calendar: calendar))"
        }
    }

    /// `2026-09-05`, in the driver's own calendar so the day in the name is the
    /// day they worked.
    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        string(date, format: "yyyy-MM-dd", calendar: calendar)
    }

    /// A machine-written date in the driver's own time zone.
    ///
    /// Fixed format, fixed locale: a file name is not a display string, and a
    /// device set to a non-Gregorian calendar or a locale that writes dates with
    /// slashes in them must still produce a name that sorts, parses and is legal
    /// on every filesystem.
    private static func string(_ date: Date, format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
