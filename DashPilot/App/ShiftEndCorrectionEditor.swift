import SwiftData
import SwiftUI

/// Choosing the moment a finished shift actually ended.
///
/// ## What the driver is really changing
///
/// One instant, and everything the app divides by it. The screen says so before
/// anything is written: the end it records now, the end being proposed, and what
/// the shift's elapsed and working times become. A screen that showed only a
/// picker would hide the consequence, and the working duration is what every
/// hourly figure in DashPilot divides by.
///
/// ## The route warning is not a footnote
///
/// Moving the end **earlier** takes route out of the shift, and those positions
/// are deleted rather than hidden. That is stated on this sheet as soon as the
/// picker passes a position, with the count, and it is confirmed in an alert
/// before anything is written. Moving the end **later** adds nothing: the sheet
/// says that too, because a driver who has just extended a shift by half an hour
/// might reasonably expect the mileage to have grown, and it has not and must
/// not.
///
/// ## A draft, applied on purpose
///
/// Nothing is written while the picker moves, exactly as ``ShiftPauseEditor``
/// writes nothing while its two move. **Cancel leaves the shift exactly as it
/// was**, and the figures behind the sheet do not move until Save.
///
/// ## Why it is refused rather than corrected
///
/// An instant the domain will not accept is **named and refused**, never quietly
/// clamped or nudged into the nearest acceptable one. The sentence under the
/// picker is the domain's own, written by ``ShiftEndCorrectionError`` so that
/// the refusal the driver reads and the refusal the write would raise cannot
/// drift apart.
///
/// ## The calendar is the environment's
///
/// The picker takes its calendar and time zone from the environment, and the
/// times printed here take the environment's locale, exactly as
/// ``ShiftPauseEditor`` and ``CustomRangeSheet`` read them. **Nothing here
/// reaches for `Calendar.autoupdatingCurrent`.** What the picker produces is an
/// **instant**, so an end corrected across a daylight-saving change measures the
/// hours that really passed rather than the ones the wall clock appears to show.
struct ShiftEndCorrectionEditor: View {
    /// The finished shift whose end is being corrected.
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var draftEnd: Date

    /// The confirmation raised before route is destroyed, holding the sentences
    /// the domain wrote for it. Nothing is written until it is confirmed.
    @State private var pendingTrim: ShiftEndCorrectionPrompt?

    /// What the store said when a save was refused, kept on the sheet so the
    /// driver reads it beside the time that caused it.
    @State private var saveError: String?

    init(shift: Shift) {
        self.shift = shift
        // Opens on the end the shift records, which is deliberately **not** a
        // suggestion: it is the fact being corrected, and a driver who opens
        // this by mistake and saves writes back exactly what was already there.
        // Nothing here proposes when the driver stopped, because nothing in
        // DashPilot observed it.
        _draftEnd = State(initialValue: shift.endedAt ?? shift.startedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                timeSection
                consequenceSection
            }
            .navigationTitle("Correct End Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel, keep this shift's recorded end time")
                        .accessibilityIdentifier("shiftEndCorrectionCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(refusal != nil)
                        .accessibilityLabel("Save this shift's corrected end time")
                        .accessibilityIdentifier("shiftEndCorrectionSaveButton")
                }
            }
            // An alert rather than a confirmation dialog, for the reason every
            // other destructive confirmation in this app uses one: a dialog is a
            // popover in some layouts, where iOS drops the explicit Cancel
            // button, and an action that deletes recorded positions must always
            // show both choices.
            .alert(
                pendingTrim.map { Text($0.title) } ?? Text("Remove Recorded Route"),
                isPresented: isConfirmingTrim,
                presenting: pendingTrim
            ) { prompt in
                Button(prompt.confirmTitle, role: .destructive) { apply() }
                    .accessibilityIdentifier("confirmShiftEndCorrectionButton")
                Button("Cancel", role: .cancel) { pendingTrim = nil }
            } message: { prompt in
                Text(prompt.detail)
            }
        }
    }

    // MARK: Sections

    /// What the shift records now, and what the driver is proposing instead.
    ///
    /// The recorded end is stated as a plain row above the picker rather than
    /// left to memory: the picker opens on it and then moves, so after one
    /// adjustment there would otherwise be nothing on screen saying what is
    /// being changed **from**.
    private var timeSection: some View {
        Section {
            LabeledContent("Recorded end") {
                Text(recordedEndText).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("This shift is recorded as ending at \(spokenRecordedEnd)")
            .accessibilityIdentifier("shiftEndCorrectionRecordedEnd")

            DatePicker(
                "Ended at",
                selection: $draftEnd,
                in: selectableRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("shiftEndCorrectionPicker")
        } header: {
            Text("End Time")
        } footer: {
            Text(boundsStatement)
        }
    }

    /// What the chosen instant would record, or why it records nothing.
    @ViewBuilder
    private var consequenceSection: some View {
        Section {
            if let refusal {
                let sentence = ShiftEndCorrectionError.invalidCorrection(refusal).errorDescription
                    ?? "That time cannot be recorded as this shift's end."
                DashValidationMessage(message: sentence, identifier: "shiftEndCorrectionRefusal")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(durationStatement)
                        .dashFont(.emphasis)
                        .monospacedDigit()
                    Text(metricsStatement)
                        .dashFont(.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(spokenDurationStatement). \(metricsStatement)")
                .accessibilityIdentifier("shiftEndCorrectionSummary")

                routeStatement
            }

            if let saveError {
                DashValidationMessage(message: saveError, identifier: "shiftEndCorrectionSaveError")
            }
        } header: {
            Text("Corrected Shift")
        } footer: {
            Text(
                """
                Correcting the end changes this shift's elapsed and working times and every hourly \
                figure over them. It never changes when the shift started, what you recorded it \
                paid, or anything your deliveries recorded.
                """
            )
        }
    }

    /// What happens to the route, which is the one consequence a driver cannot
    /// see anywhere else on this sheet.
    ///
    /// Three different statements, because there are three different truths: an
    /// earlier end with positions behind it destroys them, a later end adds
    /// nothing at all, and an earlier end with nothing behind it changes only the
    /// window the route is measured against.
    @ViewBuilder
    private var routeStatement: some View {
        if let sentence = routeSentence {
            Label(sentence, systemImage: departingPositionCount > 0 ? "exclamationmark.triangle.fill" : "info.circle")
                .dashFont(.body)
                .foregroundStyle(departingPositionCount > 0 ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sentence)
                .accessibilityIdentifier("shiftEndCorrectionRouteWarning")
        }
    }

    private var routeSentence: String? {
        guard let recordedEnd = shift.endedAt, draftEnd != recordedEnd else { return nil }
        guard draftEnd < recordedEnd else {
            return """
            No route or mileage is added for the extra time. DashPilot only counts distance it \
            actually recorded, so this shift's recorded mileage stays exactly as it is and the \
            stretch with nothing recorded in it is counted as a gap.
            """
        }
        guard departingPositionCount > 0 else {
            return """
            This shift recorded no positions after that time, so no recorded position is deleted. \
            Its mileage is measured again against the shorter shift.
            """
        }
        let positions = departingPositionCount == 1 ? "1 recorded position" : "\(departingPositionCount) recorded positions"
        return """
        \(positions) recorded after that time will be deleted, and this shift's recorded mileage \
        will be measured again from the positions that remain. The mileage is not reduced by the \
        same share as the time. You are asked to confirm before anything is deleted.
        """
    }

    // MARK: Wording

    private var recordedEndText: String {
        guard let endedAt = shift.endedAt else { return "Not recorded" }
        return endedAt.formatted(.dateTime.hour().minute().locale(locale))
    }

    private var spokenRecordedEnd: String {
        guard let endedAt = shift.endedAt else { return "no time" }
        return endedAt.formatted(date: .omitted, time: .shortened)
    }

    /// The stretch the picker may choose within.
    ///
    /// Bounded below by the shift's own start, so an end before it cannot be
    /// chosen at all and the corresponding refusal is a backstop rather than the
    /// ordinary way a driver meets the rule. Bounded above by the next shift's
    /// start where there is one, for the same reason.
    ///
    /// The remaining rules — the pauses and the deliveries — depend on facts a
    /// picker bound cannot express and are stated below it instead.
    ///
    /// A reversed range traps, so the upper bound is never allowed below the
    /// lower one. That can only happen in a store the app cannot write, where
    /// another shift began before this one's start.
    private var selectableRange: ClosedRange<Date> {
        let lower = shift.startedAt
        let upper = max(lower, latestSelectableEnd)
        return lower...upper
    }

    /// The latest instant the picker offers: the next shift's start if there is
    /// one, and otherwise the shift's own recorded end plus a day.
    ///
    /// The day is a **picker bound and nothing else** — no rule refuses an end
    /// beyond it, and a driver who needs one further out is correcting something
    /// this editor was not built for. It exists because a picker needs an upper
    /// bound and the alternative was no bound at all, which offers a shift that
    /// ended in 2049.
    private var latestSelectableEnd: Date {
        if let next = nextShiftStart { return next }
        return (shift.endedAt ?? shift.startedAt).addingTimeInterval(24 * 3600)
    }

    private var boundsStatement: String {
        let start = shift.startedAt.formatted(.dateTime.hour().minute().locale(locale))
        var sentence = "The end has to be after this shift started, at \(start)"
        if let next = nextShiftStart {
            sentence += ", and before the next shift began, at \(next.formatted(.dateTime.hour().minute().locale(locale)))"
        }
        sentence += ". It also has to be after everything this shift's deliveries and pauses recorded."
        return sentence
    }

    private var durationStatement: String {
        "\(DurationText.short(draftElapsed)) elapsed"
    }

    private var spokenDurationStatement: String {
        "\(DurationText.spoken(draftElapsed)) elapsed"
    }

    /// What the two durations every rate hangs from become.
    ///
    /// The working figure is stated separately only when it differs, which is
    /// exactly when this shift records a pause. Two identical figures side by
    /// side would invite a driver to look for a difference that does not exist,
    /// which is the same rule the detail screen's own rows follow.
    private var metricsStatement: String {
        let working = draftWorking
        var sentence = "This shift's elapsed time becomes \(DurationText.short(draftElapsed))"
        if abs(working - draftElapsed) >= 1 {
            sentence += ", and its working time \(DurationText.short(working)), which is what the hourly figures divide by"
        } else {
            sentence += ", which is what the hourly figures divide by"
        }
        sentence += ". Its start time, its recorded amount and its deliveries do not change."
        return sentence
    }

    // MARK: Derived values

    private var draftElapsed: TimeInterval {
        max(0, draftEnd.timeIntervalSince(shift.startedAt))
    }

    /// The working duration this correction would leave.
    ///
    /// Derived with the shift's own calculation over the **proposed** window
    /// rather than with a second rule: the pauses are clipped to it exactly as
    /// they are clipped to the recorded one, so a pause that a shorter shift no
    /// longer fully contains contributes only the part that is still inside.
    private var draftWorking: TimeInterval {
        let window = shift.startedAt...max(shift.startedAt, draftEnd)
        let paused = ShiftPausedTimeCalculator().pausedTime(of: shift.pauseIntervals, within: window)
        return max(0, draftElapsed - paused.duration)
    }

    /// How many retained positions the current draft would delete.
    private var departingPositionCount: Int {
        service.routeEvidenceCount(on: shift, after: draftEnd)
    }

    /// When the next shift recorded after this one began, read for the picker's
    /// upper bound and for the sentence under it.
    ///
    /// Read from the store rather than passed in, so the bound and the rule the
    /// write consults are looking at the same rows.
    private var nextShiftStart: Date? {
        var descriptor = FetchDescriptor<Shift>(
            predicate: shiftsAfterThisOne,
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first?.startedAt
    }

    private var shiftsAfterThisOne: Predicate<Shift> {
        let startedAt = shift.startedAt
        let shiftID = shift.id
        return #Predicate { $0.startedAt >= startedAt && $0.id != shiftID }
    }

    // MARK: Writing

    /// Why the current draft would be refused, or `nil` if it would be accepted.
    ///
    /// Asked of the service, which asks the domain, so the sentence on screen and
    /// the rule the write consults are the same thing rather than two opinions
    /// about it.
    private var refusal: ShiftEndCorrectionRefusal? {
        service.refusal(on: shift, to: draftEnd)
    }

    private var service: ShiftEndCorrectionService {
        ShiftEndCorrectionService(context: modelContext)
    }

    private var isConfirmingTrim: Binding<Bool> {
        Binding(
            get: { pendingTrim != nil },
            set: { isShowing in if !isShowing { pendingTrim = nil } }
        )
    }

    /// Raises the confirmation when route would be destroyed, and writes
    /// directly when none would be.
    ///
    /// A correction that deletes nothing destroys nothing, and asking a driver
    /// to confirm a deletion that is not happening teaches them to confirm
    /// without reading.
    private func save() {
        saveError = nil
        let departing = departingPositionCount
        guard departing > 0 else {
            apply()
            return
        }
        pendingTrim = .trimmingRoute(
            positionCount: departing,
            correctedEnd: draftEnd.formatted(.dateTime.hour().minute().locale(locale))
        )
    }

    private func apply() {
        pendingTrim = nil
        saveError = nil
        do {
            try service.correct(shift, to: draftEnd)
            dismiss()
        } catch {
            // Named on the sheet rather than swallowed, and the sheet stays open
            // so the driver still has the time they chose.
            saveError = (error as? any LocalizedError)?.errorDescription
                ?? "That end time could not be saved."
        }
    }
}

#if DEBUG
#Preview("Correcting a shift's end time") {
    PreviewSupport.shiftEndCorrectionEditor()
}
#endif
