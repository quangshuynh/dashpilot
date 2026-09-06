import Foundation
import Testing
@testable import DashPilot

/// The expense record itself: what it will accept, what it refuses, and the two
/// rules that decide its category and its note.
///
/// Every amount and note below is invented.
@MainActor
@Suite("Expense record")
struct ExpenseTests {
    private let occurred = Date(timeIntervalSince1970: 1_756_000_000)

    private func money(_ string: String) throws -> Money {
        try #require(Money(exact: string))
    }

    private func expense(
        _ amount: String = "42.10",
        category: ExpenseCategory = .fuel,
        note: String = ""
    ) throws -> Expense {
        try Expense(
            occurredAt: occurred,
            amount: try money(amount),
            category: category,
            noteText: note
        )
    }

    // MARK: What it holds

    @Test("An expense holds exactly what was entered")
    func holdsWhatWasEntered() throws {
        let expense = try expense("42.10", category: .fuel, note: "Half tank")

        #expect(expense.amount == Money(exact: "42.10"))
        #expect(expense.amount.amount == Decimal(string: "42.10"), "The exact decimal, not a binary neighbour")
        #expect(expense.category == .fuel)
        #expect(expense.note == "Half tank")
        #expect(expense.occurredAt == occurred)
    }

    @Test("A recorded zero is a recorded amount")
    func zeroIsRecorded() throws {
        let expense = try expense("0.00")

        #expect(expense.amount == Money.zero)
        #expect(expense.amount.isZero)
    }

    @Test("A negative amount is refused")
    func refusesNegative() throws {
        #expect(throws: ExpenseError.negativeAmount) {
            try Expense(occurredAt: occurred, amount: Money(minorUnits: -1), category: .fuel)
        }

        let expense = try expense()
        #expect(throws: ExpenseError.negativeAmount) {
            try expense.update(
                occurredAt: occurred,
                amount: Money(minorUnits: -500),
                category: .fuel,
                noteText: ""
            )
        }
        #expect(expense.amount == Money(exact: "42.10"), "A refused edit changes nothing")
    }

    // MARK: Editing

    @Test("An edit replaces every recorded fact at once")
    func editReplacesEverything() throws {
        let expense = try expense("42.10", category: .fuel, note: "Half tank")
        let later = occurred.addingTimeInterval(86_400)

        try expense.update(
            occurredAt: later,
            amount: try money("89.99"),
            category: .maintenance,
            noteText: "Oil change"
        )

        #expect(expense.amount == Money(exact: "89.99"))
        #expect(expense.category == .maintenance)
        #expect(expense.note == "Oil change")
        #expect(expense.occurredAt == later)
    }

    @Test("Clearing the note removes it rather than storing an empty one")
    func clearingTheNote() throws {
        let expense = try expense(note: "Half tank")

        try expense.update(occurredAt: occurred, amount: try money("42.10"), category: .fuel, noteText: "   ")

        #expect(expense.note == nil, "Whitespace is no note, not an empty note")
    }

    // MARK: Notes

    @Test("A note is trimmed, and whitespace alone is no note at all")
    func trimsTheNote() throws {
        #expect(try ExpenseNote.note(from: "  Front tyres  ") == "Front tyres")
        #expect(try ExpenseNote.note(from: "") == nil)
        #expect(try ExpenseNote.note(from: "   \n  ") == nil)
    }

    @Test("A note at the limit is accepted and one over it is refused")
    func noteLength() throws {
        let limit = ExpenseNote.maximumLength
        let atLimit = String(repeating: "a", count: limit)

        #expect(try ExpenseNote.note(from: atLimit) == atLimit)
        #expect(throws: ExpenseNoteError.tooLong(maximumLength: limit)) {
            try ExpenseNote.note(from: String(repeating: "a", count: limit + 1))
        }
        // Measured after trimming, so trailing spaces cannot push a legal note
        // over the edge.
        #expect(try ExpenseNote.note(from: atLimit + "   ") == atLimit)
    }

    @Test("A note that is too long is refused by the model, and nothing is written")
    func modelRefusesALongNote() throws {
        let tooLong = String(repeating: "b", count: ExpenseNote.maximumLength + 1)

        #expect(throws: ExpenseError.invalidNote(.tooLong(maximumLength: ExpenseNote.maximumLength))) {
            try Expense(occurredAt: occurred, amount: Money(minorUnits: 100), category: .other, noteText: tooLong)
        }

        let expense = try expense(note: "Half tank")
        #expect(throws: ExpenseError.self) {
            try expense.update(
                occurredAt: occurred,
                amount: try money("1.00"),
                category: .other,
                noteText: tooLong
            )
        }
        #expect(expense.note == "Half tank", "A refused edit leaves every field alone")
        #expect(expense.amount == Money(exact: "42.10"))
        #expect(expense.category == .fuel)
    }

    @Test("A note counts characters as they are read, not bytes")
    func noteCountsCharacters() throws {
        // An accented letter and an emoji are one character each on screen, and
        // several bytes each in UTF-8. The limit is the one a driver can see.
        let note = String(repeating: "é", count: ExpenseNote.maximumLength)

        #expect(try ExpenseNote.note(from: note)?.count == ExpenseNote.maximumLength)
    }

    // MARK: Categories

    @Test("The categories are the five conservative ones, and their stored words do not drift")
    func categorySet() {
        #expect(ExpenseCategory.allCases == [.fuel, .parkingAndTolls, .maintenance, .supplies, .other])
        // The raw values are the export contract's vocabulary, so they are
        // pinned here rather than left to a rename to change quietly.
        #expect(ExpenseCategory.allCases.map(\.rawValue) == [
            "fuel", "parkingAndTolls", "maintenance", "supplies", "other"
        ])
    }

    @Test("No category is a tax classification")
    func categoriesMakeNoTaxClaim() {
        let words = ExpenseCategory.allCases.flatMap { [$0.title.lowercased(), $0.rawValue.lowercased()] }
        let forbidden = ["deduct", "tax", "write-off", "writeoff", "depreciat", "mileage allowance", "business"]

        for word in forbidden {
            #expect(!words.contains { $0.contains(word) }, "No category may imply a tax treatment: \(word)")
        }
    }

    @Test("A stored category this build cannot name reads as other, which claims nothing")
    func unrecognisedCategory() {
        // Reachable only by running an older build against a newer store. The
        // amount, date and note are still the driver's records, so the row is
        // kept and labelled with the category that asserts nothing.
        #expect(ExpenseCategory.stored("fuel") == .fuel)
        #expect(ExpenseCategory.stored("chargingAtHome") == .other)
        #expect(ExpenseCategory.stored("") == .other)
    }

    @Test("An expense reduces to a record with no note in it")
    func expenseRecordDropsTheNote() throws {
        let record = try expense("6.50", category: .parkingAndTolls, note: "Garage on the corner").expenseRecord

        #expect(record.amount == Money(exact: "6.50"))
        #expect(record.category == .parkingAndTolls)
        #expect(record.occurredAt == occurred)
        // The aggregate has no use for free text, and a total has no business
        // carrying it around.
        #expect(!"\(record)".contains("Garage"))
    }

    @Test("Ordering is newest first and never ambiguous")
    func ordering() throws {
        let earlier = try expense()
        let later = try Expense(
            occurredAt: occurred.addingTimeInterval(60),
            amount: Money(minorUnits: 100),
            category: .other
        )

        #expect(Expense.recordedBefore(later, earlier))
        #expect(!Expense.recordedBefore(earlier, later))

        // Two costs recorded for the same instant still have exactly one order,
        // so a list cannot reshuffle itself between two reads.
        let sameInstant = try expense()
        let orderedForwards = Expense.recordedBefore(earlier, sameInstant)
        let orderedBackwards = Expense.recordedBefore(sameInstant, earlier)
        #expect(orderedForwards != orderedBackwards)
        #expect(orderedForwards == (earlier.id.uuidString < sameInstant.id.uuidString))
    }
}
