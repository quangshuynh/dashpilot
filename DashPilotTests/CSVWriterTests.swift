import Foundation
import Testing
@testable import DashPilot

/// RFC 4180 quoting, and the spreadsheet-safety rule that quoting alone does not
/// give.
///
/// The writer is a pure value, so every case here is one string in and one
/// string out. That is deliberate: a misaligned CSV does not crash and does not
/// look wrong, so the only place the rules can be held is a test that names each
/// character.
@Suite("CSV field quoting")
struct CSVFieldQuotingTests {
    @Test("A plain field is written bare")
    func plainField() {
        #expect(CSVWriter.field("Delivered") == "Delivered")
        #expect(CSVWriter.field("2026-09-05T13:04:05Z") == "2026-09-05T13:04:05Z")
        #expect(CSVWriter.field("86.25") == "86.25")
        #expect(CSVWriter.field("") == "")
    }

    @Test("A comma forces quoting")
    func comma() {
        #expect(CSVWriter.field("Nowhere Noodles, Downtown") == "\"Nowhere Noodles, Downtown\"")
    }

    @Test("A quotation mark is doubled inside quotes")
    func quotationMark() {
        #expect(CSVWriter.field("The \"Example\" Diner") == "\"The \"\"Example\"\" Diner\"")
    }

    @Test("A field that is only a quotation mark still round-trips")
    func loneQuotationMark() {
        #expect(CSVWriter.field("\"") == "\"\"\"\"")
    }

    @Test("A line feed is preserved inside quotes rather than rewritten")
    func lineFeed() {
        #expect(CSVWriter.field("Nowhere\nNoodles") == "\"Nowhere\nNoodles\"")
    }

    @Test("A carriage return is guarded and then quoted")
    func carriageReturn() {
        // A leading CR is also a formula leader, because a spreadsheet strips it
        // and reads what follows.
        #expect(CSVWriter.field("\rNoodles") == "\"'\rNoodles\"")
        #expect(CSVWriter.field("Nowhere\r\nNoodles") == "\"Nowhere\r\nNoodles\"")
    }

    @Test("Unicode passes through untouched")
    func unicode() {
        #expect(CSVWriter.field("Nowhere Noodles 🍜") == "Nowhere Noodles 🍜")
        #expect(CSVWriter.field("Café Ünïcode") == "Café Ünïcode")
        #expect(CSVWriter.field("のどか") == "のどか")
    }

    @Test("Leading and trailing whitespace is kept by quoting")
    func edgeWhitespace() {
        #expect(CSVWriter.field(" Example Diner") == "\" Example Diner\"")
        #expect(CSVWriter.field("Example Diner ") == "\"Example Diner \"")
        // An interior space needs nothing.
        #expect(CSVWriter.field("Example Diner") == "Example Diner")
    }
}

/// The formula-injection rule, on the one field a driver types.
///
/// A pickup place is free text. A spreadsheet reading `=NOWHERE()` as a formula
/// is the difference between a file of records and a file that runs something,
/// and RFC 4180 quotes do not prevent it: the parser strips them long before the
/// cell reaches the formula engine.
@Suite("CSV spreadsheet safety")
struct CSVSpreadsheetSafetyTests {
    @Test(
        "A field beginning with a formula character is guarded and quoted",
        arguments: [
            "=NOWHERE()",
            "+Example",
            "-Test",
            "@Diner"
        ]
    )
    func formulaLeadersAreGuarded(name: String) {
        let field = CSVWriter.field(name)
        #expect(field == "\"'\(name)\"")
        // The guard is in front of the original text, not instead of it: the
        // name the driver typed is still in the file.
        #expect(field.contains(name))
    }

    @Test("A tab is treated as a formula leader, because a spreadsheet strips it")
    func tabLeader() {
        #expect(CSVWriter.field("\t=NOWHERE()") == "\"'\t=NOWHERE()\"")
    }

    @Test("A formula character anywhere but the front is left alone")
    func interiorFormulaCharacter() {
        #expect(CSVWriter.field("Nowhere=Noodles") == "Nowhere=Noodles")
        #expect(CSVWriter.field("Fish-n-Chips") == "Fish-n-Chips")
        #expect(CSVWriter.field("mail@example") == "mail@example")
    }

    @Test("A guarded field is always quoted, so the guard cannot be read as syntax")
    func guardedFieldsAreQuoted() {
        for name in ["=NOWHERE()", "+Example", "-Test", "@Diner"] {
            let field = CSVWriter.field(name)
            #expect(field.hasPrefix("\"'"))
            #expect(field.hasSuffix("\""))
        }
    }

    @Test("Quoting alone is not relied on")
    func guardIsNotJustQuoting() {
        // The proof that the rule is more than quoting: strip the RFC 4180
        // quotes the way any parser does, and the cell still does not begin
        // with a formula character.
        let stripped = CSVWriter.field("=NOWHERE()").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        #expect(stripped.first == "'")
    }

    @Test("Nothing DashPilot generates is altered by the guard")
    func generatedFieldsAreUnchanged() {
        // Timestamps start with a digit, amounts are never negative, states and
        // route statuses are words. If any of those ever changed, the guard
        // would quietly start rewriting them, and this is where it would show.
        let generated = [
            "2026-09-05T13:04:05Z", "86.25", "0.00", "delivered", "cancelled",
            "measured", "noRouteRecorded", "true", "false", "3", "USD"
        ]
        for field in generated {
            #expect(CSVWriter.formulaSafe(field) == field)
            #expect(CSVWriter.field(field) == field)
        }
    }
}

/// Whole records: separators, terminators and the shape of the file.
@Suite("CSV records")
struct CSVRecordTests {
    @Test("An empty writer produces no text at all")
    func empty() {
        #expect(CSVWriter().text.isEmpty)
    }

    @Test("Records are separated and terminated with CRLF")
    func lineTerminators() {
        var writer = CSVWriter()
        writer.appendRow(["a", "b"])
        writer.appendRow(["c", "d"])
        #expect(writer.text == "a,b\r\nc,d\r\n")
    }

    @Test("A quoted field's own line breaks do not end the record")
    func embeddedNewlineDoesNotEndTheRecord() {
        var writer = CSVWriter()
        writer.appendRow(["Nowhere\nNoodles", "86.25"])
        let text = writer.text
        #expect(text == "\"Nowhere\nNoodles\",86.25\r\n")
        // One record: exactly one CRLF, at the end.
        #expect(text.components(separatedBy: "\r\n").count == 2)
    }

    @Test("An empty cell is empty, not a zero")
    func emptyCells() {
        var writer = CSVWriter()
        writer.appendRow(["86.25", "", "", "3"])
        #expect(writer.text == "86.25,,,3\r\n")
    }

    @Test("Every row has the same field count")
    func rowShape() {
        var writer = CSVWriter()
        writer.appendRow(["a", "b", "c"])
        writer.appendRow(["", "Nowhere Noodles, Downtown", ""])
        let rows = writer.text
            .components(separatedBy: "\r\n")
            .filter { !$0.isEmpty }
        #expect(rows.count == 2)
        // The second row's comma is inside quotes, so a naive split would find
        // four fields where there are three. This is the failure the writer
        // exists to prevent.
        #expect(rows[1] == ",\"Nowhere Noodles, Downtown\",")
    }
}
