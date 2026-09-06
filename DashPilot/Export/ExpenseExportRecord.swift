import Foundation

/// One recorded expense in an exported file.
///
/// ## What it carries, and what it cannot
///
/// The four facts the driver entered, and nothing derived. There is no shift
/// identifier, no delivery identifier and no allocation of any kind, because
/// there is none to export: an expense is dated rather than attached, and
/// inventing an attribution on the way out of the app would be the same
/// fabrication the model refuses on the way in. See ``Expense``.
///
/// A consumer wanting costs beside work joins on the **date**, which is the only
/// relationship DashPilot can honestly state.
///
/// ## The note
///
/// Exported as the driver typed it, for the reason a pickup place name is: it is
/// their own record, and an export that dropped it would hand back less than
/// they entered. It is free text, so the export sheet says what leaves the
/// device before the file is written, and the CSV writer's formula guard applies
/// to it wherever it is written into a spreadsheet cell.
nonisolated struct ExpenseExportRecord: Equatable, Sendable, Codable {
    /// The expense's own persisted identifier, for the reason
    /// ``ShiftExportRecord/id`` is exported.
    let id: UUID

    /// When the cost was incurred, as the driver recorded it — never when the
    /// row was typed.
    let occurredAt: Date

    /// One of a closed set: `fuel`, `parkingAndTolls`, `maintenance`,
    /// `supplies`, `other`. ``ExpenseCategory``'s own vocabulary, so the
    /// exported word is the domain's word rather than a second set of spellings
    /// invented for the wire.
    let category: ExpenseCategory

    /// What it cost. Always present: an expense with no amount is not a record
    /// of anything, which is why this is the one amount in the format that is
    /// never `null`. A recorded `0.00` is a real recorded amount.
    let amount: ExportAmount

    /// The currency the amount is in, stated per record for the reason
    /// ``ShiftExportRecord/currencyCode`` is stated per shift.
    let currencyCode: String

    /// The driver's own short reminder, or `null` when they wrote none.
    let note: String?

    init(_ expense: Expense) {
        id = expense.id
        occurredAt = expense.occurredAt
        category = expense.category
        amount = ExportAmount(expense.amount)
        currencyCode = Money.displayCurrencyCode
        note = expense.note
    }

    private enum CodingKeys: String, CodingKey {
        case id, occurredAt, category, amount, currencyCode, note
    }

    /// Written with explicit `null`s. See ``ExportDocument`` for why.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(category, forKey: .category)
        try container.encode(amount, forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encodeAlways(note, forKey: .note)
    }
}
