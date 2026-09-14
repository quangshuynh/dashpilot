import Foundation

/// One of a shift's pauses together with the number the interface calls it.
///
/// ## The number is presentation, and it is local
///
/// A finished shift can hold several pauses, and a driver correcting one has to
/// be able to tell two rows and two controls apart. A pause carries nothing that
/// could name it — no place, no reason, no label, because DashPilot records
/// none of those — so what is left is a count: `Pause 1`, `Pause 2`, taken from
/// the order the shift recorded them in.
///
/// It is **not** an identifier. ``ShiftPause/id`` is never shown, spoken or put
/// in a control's accessibility label, which is the rule every other screen here
/// keeps.
///
/// ## Nothing about it is persisted
///
/// Storing a display number would be a second answer to a question the start
/// timestamps already answer. Unlike a delivery's number, a pause's **can**
/// change: correcting a pause's start can move it past another one, and
/// deleting a pause renumbers the pauses after it. That is why nothing mutates
/// through the number.
///
/// ## Nothing mutates through it
///
/// Every control the interface builds from a numbered pause acts on ``pause``,
/// the persisted row, so a renumbering between drawing a control and pressing it
/// could not send a correction to the wrong record.
nonisolated struct NumberedPause: Identifiable {
    let number: Int
    let pause: ShiftPause

    var id: UUID { pause.id }

    /// Numbers pauses in the order they began.
    ///
    /// The order is ``Shift/pausesInOrder``'s, rather than however a
    /// relationship happened to return them, so the same pauses always get the
    /// same numbers.
    static func numbering(_ pauses: some Sequence<ShiftPause>) -> [NumberedPause] {
        pauses
            .sorted { $0.startedAt < $1.startedAt }
            .enumerated()
            .map { NumberedPause(number: $0.offset + 1, pause: $0.element) }
    }

    /// What this pause is called on screen.
    var title: String { Self.title(number: number) }

    /// The same name built from a number alone, for a caller that has the number
    /// but not the row.
    static func title(number: Int) -> String { "Pause \(number)" }

    /// What VoiceOver hears for this pause's Edit control.
    ///
    /// The pause is named first. With several rows on screen, a button saying
    /// only "Edit Pause" identifies its target by nothing but where it happens
    /// to sit, which is unusable without sight.
    var spokenEditLabel: String { "Edit \(title). Change when this pause started and ended" }

    /// What VoiceOver hears for this pause's Delete control.
    ///
    /// It says what deleting means rather than only that something will be
    /// removed: a driver deleting a pause is recording that they were never
    /// paused then.
    var spokenDeleteLabel: String { "Delete \(title). Record that this pause did not happen" }
}
