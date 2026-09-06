import Foundation

/// What a driver asked to export.
///
/// Three shapes of scope, and every one of them is *history*. A running shift is
/// not a scope and cannot be reached from one: its elapsed time is still
/// growing, it has no finalised amount, and a file claiming to be the record of
/// it would be out of date before it finished writing.
nonisolated enum ExportScope: Equatable, Sendable, Hashable {
    /// One completed shift, identified by its own persisted identifier.
    case shift(UUID)
    /// Every completed shift belonging to one reporting period — a calendar
    /// day, week or month, or a range the driver chose — by the same membership
    /// rule the period summary uses. See ``ReportingPeriod/contains(_:)``.
    ///
    /// One case for all four, deliberately: a month and a custom range are new
    /// *boundaries*, and giving either its own scope case would be the first
    /// step towards them selecting records by a second set of rules.
    case period(ReportingPeriod)
    /// Every completed shift in the store.
    case allHistory

    /// The stable word written into the file: `shift`, `day`, `week`, `month`,
    /// `custom` or `allHistory`.
    ///
    /// `month` and `custom` were added in format version 2 — see
    /// ``ExportFormat``.
    var kind: String {
        switch self {
        case .shift: "shift"
        case let .period(period): period.unit.rawValue
        case .allHistory: "allHistory"
        }
    }

    /// The period this scope covers, or `nil` for the two that are not calendar
    /// spans.
    var period: ReportingPeriod? {
        switch self {
        case let .period(period): period
        case .shift, .allHistory: nil
        }
    }

    /// What the control that starts this export says.
    ///
    /// A custom range is `Export Range` rather than `Export Custom`: the word
    /// names the thing being exported, and "custom" describes how it was chosen.
    var actionTitle: String {
        switch self {
        case .shift: "Export Shift"
        case let .period(period): period.unit == .custom ? "Export Range" : "Export \(period.unit.title)"
        case .allHistory: "Export All History"
        }
    }

    /// What VoiceOver hears on that control. A verb and a scope, because a
    /// screen can offer more than one.
    var spokenActionLabel: String {
        switch self {
        case .shift: "Export this shift"
        case let .period(period): "Export this \(period.unit.stepNoun)"
        case .allHistory: "Export all completed shifts"
        }
    }
}

/// The scope, written into the file so it says what it is a record of.
///
/// ## One interpretation of a period, everywhere
///
/// The bounds written here are the period's own — the same
/// `[periodStart, periodEndExclusive)` the summary screen counted shifts by.
/// Export does not re-describe a range in a friendlier way: a file whose
/// boundaries meant something slightly different from the screen's would be
/// impossible to reconcile later, and the driver would have no way to tell which
/// was right.
nonisolated struct ExportScopeRecord: Equatable, Sendable, Codable {
    /// `shift`, `day`, `week`, `month`, `custom` or `allHistory`.
    ///
    /// `month` and `custom` are format-version-2 values. `custom` is a range the
    /// driver selected by two inclusive calendar dates; every other period value
    /// is a span the driver's calendar defines.
    let kind: String

    /// The first instant of the period, or `null` when the scope is not one.
    let periodStart: Date?

    /// The first instant **after** the period. Never part of it.
    ///
    /// Half-open, for the reason ``ReportingPeriod`` is: a shift starting at
    /// exactly midnight belongs to one day and not to two. The key says
    /// `Exclusive` because that is the part a reader gets wrong — a range the
    /// driver chose as *September 1 through 7* is written as ending at the start
    /// of September 8, and the name has to make that unmistakable rather than
    /// leave it to a comment in a document nobody exported.
    let periodEndExclusive: Date?

    init(_ scope: ExportScope) {
        kind = scope.kind
        periodStart = scope.period?.start
        periodEndExclusive = scope.period?.end
    }

    private enum CodingKeys: String, CodingKey {
        case kind, periodStart, periodEndExclusive
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeAlways(periodStart, forKey: .periodStart)
        try container.encodeAlways(periodEndExclusive, forKey: .periodEndExclusive)
    }
}

/// One exported file, as a value.
///
/// ## The contract
///
/// This is the whole of what DashPilot writes out, and it is deliberately a
/// **record of what the app has recorded** rather than a report. It contains no
/// figure the app does not already show, no reconciliation between the two kinds
/// of amount, no projection and no score.
///
/// ## Explicit `null`, everywhere
///
/// Every optional field is written as `null` rather than omitted. One
/// convention, chosen so that a reader can tell "DashPilot did not record this"
/// from "this build of DashPilot has no such field" without knowing the full key
/// set, and so that every record in an array is the same shape. See
/// ``KeyedEncodingContainer/encodeAlways(_:forKey:)``.
///
/// ## Metadata, and what is not in it
///
/// The format version, when the file was written, what it covers and how many
/// shifts it holds. Deliberately **not**: the device's name, model or time zone,
/// the driver's name or Apple Account, a home or work location, or any
/// identifier that would let two exports be tied to one person by anything other
/// than their contents.
nonisolated struct ExportDocument: Equatable, Sendable, Codable {
    /// The **file format** version, which is not the store's schema version.
    /// See ``ExportFormat``.
    let formatVersion: Int

    /// `DashPilot`. A product name, not a build or a device.
    let producer: String

    /// When this file was written.
    let exportedAt: Date

    let scope: ExportScopeRecord

    /// How many completed shifts the file holds. Stated as well as derivable,
    /// so a truncated or partially read file is obvious.
    let shiftCount: Int

    /// Newest first, matching the order history is read in.
    let shifts: [ShiftExportRecord]

    /// The operating costs the driver recorded in this scope, newest first.
    ///
    /// Selected by the expenses' **own** dates: a period scope holds the
    /// expenses dated inside it, and an all-history scope holds every one.
    ///
    /// **Always empty for a single-shift scope**, and that is a statement about
    /// the model rather than a gap in the export. An expense is dated, not
    /// attached to a shift, so DashPilot cannot say which expenses belong to one
    /// shift — and picking the ones that happen to share its clock hours would
    /// invent exactly the attribution the app refuses to invent. Export the day,
    /// the week, the month or a range to get costs beside work.
    ///
    /// Present and empty rather than absent, so a reader never has to tell "no
    /// expenses" from "an older build".
    let expenses: [ExpenseExportRecord]

    /// The period's own figures with the counts behind them, or `null` for a
    /// scope that is not a calendar period.
    let summary: PeriodExportSummary?

    private enum CodingKeys: String, CodingKey {
        case formatVersion, producer, exportedAt, scope, shiftCount, shifts, expenses, summary
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(producer, forKey: .producer)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(scope, forKey: .scope)
        try container.encode(shiftCount, forKey: .shiftCount)
        try container.encode(shifts, forKey: .shifts)
        try container.encode(expenses, forKey: .expenses)
        try container.encodeAlways(summary, forKey: .summary)
    }
}

nonisolated extension ExportDocument {
    /// Assembles the document. The one place the metadata is written.
    init(
        scope: ExportScope,
        shifts: [ShiftExportRecord],
        expenses: [ExpenseExportRecord] = [],
        summary: PeriodExportSummary?,
        exportedAt: Date
    ) {
        formatVersion = ExportFormat.version
        producer = ExportFormat.producer
        self.exportedAt = exportedAt
        self.scope = ExportScopeRecord(scope)
        shiftCount = shifts.count
        self.shifts = shifts
        self.expenses = expenses
        self.summary = summary
    }
}
