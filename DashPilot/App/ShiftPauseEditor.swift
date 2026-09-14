import SwiftData
import SwiftUI

/// Choosing the two times one pause of a finished shift records.
///
/// ## One screen for three corrections
///
/// Correcting a start, correcting an end, correcting both, and adding a pause
/// the driver never recorded are the same act: choosing two instants and
/// checking them against the shift. One screen means a start moved by itself is
/// checked by exactly the rules that check a start and an end moved together,
/// and there is one place where those rules are stated to the driver.
///
/// ## A draft, applied on purpose
///
/// Nothing is written while the pickers move, exactly as ``CustomRangeSheet``
/// writes nothing while a range is chosen. **Cancel leaves the pause exactly as
/// it was**, and the shift's figures behind the sheet do not move until Save.
///
/// ## Why it is refused rather than corrected
///
/// A stretch the domain will not accept is **named and refused**, never quietly
/// clamped, swapped or nudged into the nearest acceptable one. A driver whose
/// end time landed before their start time typed something they did not mean,
/// and turning it round for them answers a question they did not ask. The
/// sentence under the pickers is the domain's own, written by
/// ``ShiftPauseCorrectionError`` so that the refusal the driver reads and the
/// refusal the write would raise cannot drift apart.
///
/// ## The calendar is the environment's
///
/// Both pickers take their calendar and time zone from the environment, and the
/// times printed here take the environment's locale, which is how
/// ``PeriodSummaryView`` and ``CustomRangeSheet`` already read them. **Nothing
/// here reaches for `Calendar.autoupdatingCurrent`**, so a pause is edited in the
/// same calendar the shift's own times and its period wording are written in,
/// and a future edit that reached for one would be reaching past the screen it
/// is on.
///
/// What the pickers produce are **instants**. A pause corrected across a
/// daylight-saving change therefore measures the hours that really passed rather
/// than the ones the wall clock appears to show, and the bounds compare instants
/// too: a time that reads as inside the shift on a wall clock that skipped an
/// hour is still refused if the instant is outside it.
struct ShiftPauseEditor: View {
    /// The shift being corrected. Its window bounds both pickers.
    let shift: Shift

    /// The pause being corrected, or `nil` when one is being added.
    ///
    /// It is the model rather than its number, so a renumbering between opening
    /// this sheet and saving could not send the correction to another row.
    let pause: NumberedPause?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var draftStart: Date
    @State private var draftEnd: Date

    /// What the store said when a save was refused, kept on the sheet so the
    /// driver reads it beside the times that caused it.
    @State private var saveError: String?

    init(shift: Shift, pause: NumberedPause? = nil) {
        self.shift = shift
        self.pause = pause

        // An existing pause opens on its own recorded times. A new one opens on
        // the shift's start for both, which is deliberately **not** a suggested
        // pause: it is the earliest instant inside the shift, it is refused as
        // it stands for having no length, and the driver has to choose both ends
        // before anything can be saved. Nothing here proposes when a break
        // happened, because nothing in DashPilot observed one.
        let start = pause?.pause.startedAt ?? shift.startedAt
        _draftStart = State(initialValue: start)
        _draftEnd = State(initialValue: pause?.pause.endedAt ?? start)
    }

    var body: some View {
        NavigationStack {
            Form {
                timesSection
                consequenceSection
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel(cancelLabel)
                        .accessibilityIdentifier("shiftPauseEditorCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(refusal != nil)
                        .accessibilityLabel(saveLabel)
                        .accessibilityIdentifier("shiftPauseEditorSaveButton")
                }
            }
        }
    }

    // MARK: Sections

    /// The two pickers, each bounded by the shift itself.
    ///
    /// The range is the shift's own window, so a time outside the shift cannot
    /// be chosen at all and the corresponding refusal is a backstop rather than
    /// the ordinary way a driver meets the rule. Every other rule — the positive
    /// length, the other pauses, the delivery work — depends on both values at
    /// once and cannot be expressed as a picker bound, so it is stated below
    /// instead.
    private var timesSection: some View {
        Section {
            DatePicker(
                "Paused at",
                selection: $draftStart,
                in: selectableRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("shiftPauseStartPicker")

            DatePicker(
                "Resumed at",
                selection: $draftEnd,
                in: selectableRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("shiftPauseEndPicker")
        } header: {
            Text("Times")
        } footer: {
            Text(shiftWindowStatement)
        }
    }

    /// What the chosen times would record, or why they record nothing.
    @ViewBuilder
    private var consequenceSection: some View {
        Section {
            if let refusal {
                let sentence = ShiftPauseCorrectionError.invalidCorrection(refusal).errorDescription
                    ?? "Those times cannot be recorded as a pause."
                Label(sentence, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    // One element carrying the sentence, rather than a glyph
                    // called "Warning" beside it: the icon is decoration, the
                    // refusal is the whole of what has to be read out, and the
                    // colour is never the only thing carrying it.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sentence)
                    .accessibilityIdentifier("shiftPauseEditorRefusal")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(durationStatement)
                        .font(.headline)
                        .monospacedDigit()
                    Text(workingTimeStatement)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(spokenDurationStatement). \(workingTimeStatement)")
                .accessibilityIdentifier("shiftPauseEditorSummary")
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(saveError)
                    .accessibilityIdentifier("shiftPauseEditorSaveError")
            }
        } header: {
            Text(pause == nil ? "Pause To Add" : "Corrected Pause")
        } footer: {
            Text(
                """
                DashPilot recorded no route while a shift was paused at the time, and correcting a \
                pause afterwards does not change the route it recorded: no position is added, moved \
                or deleted, so this shift's recorded mileage stays exactly as it is.
                """
            )
        }
    }

    // MARK: Wording

    private var navigationTitle: String {
        pause.map { "Correct \($0.title)" } ?? "Add Missed Pause"
    }

    private var cancelLabel: String {
        pause == nil ? "Cancel, add no pause" : "Cancel, keep this pause as it is"
    }

    private var saveLabel: String {
        pause.map { "Save \($0.title)" } ?? "Save this pause"
    }

    /// The stretch the pickers may choose within, which is the shift itself.
    ///
    /// A shift whose stored end precedes its start has no window, which the
    /// domain refuses anyway; the fallback keeps the picker from being handed a
    /// reversed range, which traps.
    private var selectableRange: ClosedRange<Date> {
        shift.completedWindow ?? shift.startedAt...shift.startedAt
    }

    private var shiftWindowStatement: String {
        guard let endedAt = shift.endedAt else {
            return "Pauses can be corrected once the shift has ended."
        }
        let start = shift.startedAt.formatted(.dateTime.hour().minute().locale(locale))
        let end = endedAt.formatted(.dateTime.hour().minute().locale(locale))
        return """
        Both times have to be inside this shift, which ran from \(start) to \(end), and a pause \
        cannot overlap another pause or a delivery you recorded.
        """
    }

    private var durationStatement: String {
        "\(DurationText.short(draftEnd.timeIntervalSince(draftStart))) paused"
    }

    private var spokenDurationStatement: String {
        "\(DurationText.spoken(draftEnd.timeIntervalSince(draftStart))) paused"
    }

    /// What the shift's working duration becomes, stated before anything is
    /// written.
    ///
    /// The figure the driver is really changing. A pause screen that showed only
    /// two times would hide the consequence: the working duration is what every
    /// hourly figure in the app divides by.
    private var workingTimeStatement: String {
        guard let elapsed = shift.completedDuration else {
            return "This shift's working time is its elapsed time less the stretches you were paused."
        }
        let projected = max(0, elapsed - projectedPausedDuration)
        return """
        This shift's working time becomes \(DurationText.short(projected)), which is its \
        \(DurationText.short(elapsed)) less every pause it records. Its elapsed time, its recorded \
        mileage and the amounts you entered do not change.
        """
    }

    /// The shift's paused total if this correction were saved.
    ///
    /// Unioned rather than added, by the same rule the shift itself uses, so a
    /// corrected pause that touches another does not count a shared second
    /// twice.
    private var projectedPausedDuration: TimeInterval {
        guard let window = shift.completedWindow else { return 0 }
        var intervals = shift.pauses
            .filter { $0.id != pause?.id }
            .map(\.interval)
        intervals.append(ShiftPauseInterval(start: draftStart, end: draftEnd))
        return ShiftPausedTimeCalculator().pausedTime(of: intervals, within: window).duration
    }

    // MARK: Writing

    /// Why the current draft would be refused, or `nil` if it would be accepted.
    ///
    /// Asked of the service, which asks the domain, so the sentence on screen and
    /// the rule the write consults are the same thing rather than two opinions
    /// about it.
    private var refusal: ShiftPauseCorrectionRefusal? {
        ShiftPauseCorrectionService(context: modelContext).refusal(
            correcting: pause?.pause,
            on: shift,
            from: draftStart,
            to: draftEnd
        )
    }

    private func save() {
        saveError = nil
        let service = ShiftPauseCorrectionService(context: modelContext)
        do {
            if let pause {
                try service.correct(pause.pause, from: draftStart, to: draftEnd)
            } else {
                try service.addMissedPause(on: shift, from: draftStart, to: draftEnd)
            }
            dismiss()
        } catch {
            // Named on the sheet rather than swallowed, and the sheet stays open
            // so the driver still has the times they chose.
            saveError = (error as? any LocalizedError)?.errorDescription
                ?? "That pause could not be saved."
        }
    }
}

#if DEBUG
#Preview("Correcting a recorded pause") {
    PreviewSupport.shiftPauseEditor(correctingFirstPause: true)
}

#Preview("Adding a missed pause") {
    PreviewSupport.shiftPauseEditor(correctingFirstPause: false)
}
#endif
