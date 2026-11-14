import SwiftData
import SwiftUI

/// Correcting when a shift started and, once it has finished, when it ended.
///
/// ## What the driver sees before saving
///
/// The times the shift records now, the two pickers, and what the shift becomes:
/// its duration beside the duration it had, its working time where it was
/// paused, the reporting period it moves into when the start crosses a day,
/// and what happens to its route. Every hourly figure divides by the working
/// time this sheet changes, so the consequence is stated rather than left to be
/// discovered on the detail screen.
///
/// ## A draft, applied on purpose
///
/// Nothing is written while a picker moves. **Cancel leaves the shift exactly
/// as it was.** Save is withheld while either time is refused, and the refusal
/// is the domain's own sentence, shown under the picker it belongs to. An
/// ordinary valid edit saves at once; only one that deletes recorded positions
/// asks first, because that cannot be undone.
///
/// ## Running shifts
///
/// A running shift offers its start alone. Saving neither pauses nor ends it,
/// and the Live Activity is reconciled so the Lock Screen counts from the
/// corrected start too.
///
/// ## The calendar is the environment's
///
/// Pickers and printed times use the environment's calendar, time zone and
/// locale. What a picker produces is an instant, so a correction across a
/// daylight-saving change measures the hours that really passed.
struct ShiftTimeCorrectionEditor: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    /// Present wherever a running shift can be shown; absent in some previews.
    @Environment(ShiftLiveActivityService.self) private var liveActivity: ShiftLiveActivityService?

    @State private var draftStart: Date
    @State private var draftEnd: Date
    @State private var neighbours: ShiftTimeNeighbours = .none
    @State private var pendingTrim: ShiftTimeCorrectionPrompt?
    @State private var saveError: String?

    /// The longest stretch a picker offers beyond a recorded time when no
    /// neighbouring shift bounds it. A picker bound and nothing else: no rule
    /// refuses a time past it.
    private static let pickerReach: TimeInterval = 24 * 3600

    init(shift: Shift) {
        self.shift = shift
        // Opens on the recorded times, which are the facts being corrected and
        // not a suggestion: saving without moving anything writes nothing.
        _draftStart = State(initialValue: shift.startedAt)
        _draftEnd = State(initialValue: shift.endedAt ?? shift.startedAt)
    }

    private var isRunning: Bool { shift.endedAt == nil }
    private var proposedEnd: Date? { isRunning ? nil : draftEnd }

    var body: some View {
        NavigationStack {
            Form {
                recordedSection
                pickerSection
                consequenceSection
            }
            .navigationTitle(isRunning ? "Edit Start Time" : "Edit Shift Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel, keep this shift's recorded times")
                        .accessibilityIdentifier("shiftTimeCorrectionCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(refusal != nil || !changesAnything)
                        .accessibilityLabel("Save this shift's corrected times")
                        .accessibilityIdentifier("shiftTimeCorrectionSaveButton")
                }
            }
            .onAppear { neighbours = (try? service.neighbours(of: shift, proposedStart: shift.startedAt)) ?? .none }
            // An alert rather than a confirmation dialog, as every destructive
            // confirmation in this app is: both choices always on screen.
            .alert(
                pendingTrim.map { Text($0.title) } ?? Text("Remove Recorded Route"),
                isPresented: isConfirmingTrim,
                presenting: pendingTrim
            ) { prompt in
                Button(prompt.confirmTitle, role: .destructive) { apply() }
                    .accessibilityIdentifier("confirmShiftTimeCorrectionButton")
                Button("Cancel", role: .cancel) { pendingTrim = nil }
            } message: { prompt in
                Text(prompt.detail)
            }
        }
    }

    // MARK: Sections

    /// What the shift records now, stated as plain rows so there is always
    /// something on screen saying what is being changed from.
    private var recordedSection: some View {
        Section {
            LabeledContent("Started") { Text(timeText(shift.startedAt)).monospacedDigit() }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recorded start, \(spokenTime(shift.startedAt))")
                .accessibilityIdentifier("shiftTimeCorrectionRecordedStart")
            if let endedAt = shift.endedAt {
                LabeledContent("Ended") { Text(timeText(endedAt)).monospacedDigit() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recorded end, \(spokenTime(endedAt))")
                    .accessibilityIdentifier("shiftTimeCorrectionRecordedEnd")
                LabeledContent("Duration") { Text(DurationText.short(shift.elapsed(asOf: endedAt))).monospacedDigit() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recorded duration, \(DurationText.spoken(shift.elapsed(asOf: endedAt)))")
                    .accessibilityIdentifier("shiftTimeCorrectionRecordedDuration")
            }
        } header: {
            Text("Recorded")
        }
    }

    private var pickerSection: some View {
        Section {
            DatePicker("Started", selection: $draftStart, in: startRange, displayedComponents: [.date, .hourAndMinute])
                .accessibilityIdentifier("shiftTimeCorrectionStartPicker")
            if case let .start(refusal)? = refusal {
                DashValidationMessage(
                    message: ShiftTimeCorrectionError.sentence(for: refusal),
                    identifier: "shiftTimeCorrectionStartRefusal"
                )
            }
            if !isRunning {
                DatePicker("Ended", selection: $draftEnd, in: endRange, displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("shiftTimeCorrectionEndPicker")
                if case let .end(refusal)? = refusal {
                    DashValidationMessage(
                        message: ShiftTimeCorrectionError.invalidCorrection(.end(refusal)).errorDescription
                            ?? "That end time cannot be recorded.",
                        identifier: "shiftTimeCorrectionEndRefusal"
                    )
                }
            }
        } header: {
            Text(isRunning ? "Corrected Start" : "Corrected Times")
        } footer: {
            Text(boundsStatement)
        }
    }

    @ViewBuilder
    private var consequenceSection: some View {
        Section {
            if isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    durationSummary(asOf: context.date)
                }
            } else {
                durationSummary(asOf: draftEnd)
            }
            if let move = reportingMove {
                Label(move.statement(calendar: calendar, locale: locale), systemImage: "calendar")
                    .dashFont(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(move.statement(calendar: calendar, locale: locale))
                    .accessibilityIdentifier("shiftTimeCorrectionPeriodNotice")
            }
            if let sentence = routeSentence {
                Label(sentence, systemImage: routeLoss.total > 0 ? "exclamationmark.triangle.fill" : "info.circle")
                    .dashFont(.body)
                    .foregroundStyle(routeLoss.total > 0 ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sentence)
                    .accessibilityIdentifier("shiftTimeCorrectionRouteWarning")
            }
            if let saveError {
                DashValidationMessage(message: saveError, identifier: "shiftTimeCorrectionSaveError")
            }
        } header: {
            Text("Corrected Shift")
        } footer: {
            Text(
                isRunning
                    ? """
                    The shift keeps running and its timer counts from the corrected start. Orders, pauses \
                    and your route after that time are unchanged.
                    """
                    : """
                    Duration, working time and every hourly figure follow these times. Amounts, tips, \
                    deliveries, pauses and expenses do not change.
                    """
            )
        }
    }

    /// The corrected duration beside the recorded one, and working time where
    /// pauses make it differ.
    @ViewBuilder
    private func durationSummary(asOf reference: Date) -> some View {
        let recordedElapsed = shift.elapsed(asOf: isRunning ? reference : (shift.endedAt ?? reference))
        let elapsed = max(0, (proposedEnd ?? reference).timeIntervalSince(draftStart))
        let working = correctedWorking(asOf: reference)
        let title = isRunning ? "Working time so far" : "Duration"
        let value = isRunning ? working : elapsed
        let before = isRunning ? shift.workingDuration(asOf: reference) : recordedElapsed
        VStack(alignment: .leading, spacing: DashSpacing.sm) {
            LabeledContent(title) {
                Text(DurationText.short(value)).monospacedDigit().dashFont(.emphasis)
            }
            if refusal == nil, changesAnything {
                Text("Was \(DurationText.short(before))")
                    .dashFont(.supporting).foregroundStyle(.secondary)
            }
            if !isRunning, shift.pausesInOrder.isEmpty == false, abs(working - elapsed) >= 1 {
                LabeledContent("Working time") { Text(DurationText.short(working)).monospacedDigit() }
                    .dashFont(.supporting)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title), \(DurationText.spoken(value))"
                + (changesAnything ? ", was \(DurationText.spoken(before))" : "")
        )
        .accessibilityIdentifier("shiftTimeCorrectionSummary")
    }

    // MARK: Derived values

    private var service: ShiftTimeCorrectionService { ShiftTimeCorrectionService(context: modelContext) }

    private var refusal: ShiftTimeCorrectionRefusal? {
        service.refusal(on: shift, start: draftStart, end: proposedEnd)
    }

    private var changesAnything: Bool {
        draftStart != shift.startedAt || (proposedEnd != nil && proposedEnd != shift.endedAt)
    }

    private var routeLoss: ShiftRouteEvidenceLoss {
        service.routeEvidenceLoss(on: shift, start: draftStart, end: proposedEnd)
    }

    private var reportingMove: ShiftReportingMove? {
        ShiftReportingMove(from: shift.startedAt, to: draftStart, calendar: calendar)
    }

    /// Working time over the corrected window, by the shift's own rule.
    private func correctedWorking(asOf reference: Date) -> TimeInterval {
        let end = proposedEnd ?? reference
        let elapsed = max(0, end.timeIntervalSince(draftStart))
        let pauses = shift.pauseIntervals
        guard !pauses.isEmpty else { return elapsed }
        let window = draftStart...max(draftStart, end)
        return max(0, elapsed - ShiftPausedTimeCalculator().pausedTime(of: pauses, within: window).duration)
    }

    /// Bounded below by the previous shift's end where there is one, and above
    /// by now. Always contains the recorded start, so the picker never opens on
    /// a value it would silently clamp.
    private var startRange: ClosedRange<Date> {
        let floor = neighbours.previous?.endedAt ?? shift.startedAt.addingTimeInterval(-Self.pickerReach)
        let lower = min(floor, shift.startedAt)
        let ceiling = isRunning ? Date.now : min(Date.now, max(shift.endedAt ?? .now, draftEnd))
        return lower...max(lower, ceiling, shift.startedAt)
    }

    /// Bounded above by the next shift's start where there is one, and by now.
    private var endRange: ClosedRange<Date> {
        let recordedEnd = shift.endedAt ?? shift.startedAt
        let lower = min(shift.startedAt, draftStart)
        let reach = neighbours.nextAfterRecordedStartStartedAt ?? recordedEnd.addingTimeInterval(Self.pickerReach)
        let upper = max(min(reach, Date.now), recordedEnd)
        return lower...max(lower, upper)
    }

    private var boundsStatement: String {
        var sentences: [String] = []
        if let previousEnd = neighbours.previous?.endedAt {
            sentences.append("The start has to be after the previous shift ended, at \(timeText(previousEnd)).")
        }
        if !isRunning, let next = neighbours.nextAfterRecordedStartStartedAt {
            sentences.append("The end has to be before the next shift began, at \(timeText(next)).")
        }
        sentences.append(
            isRunning
                ? "The start has to be before everything this shift has recorded, and no later than now."
                : "Both times have to contain everything this shift's deliveries and pauses recorded, and neither can be later than now."
        )
        return sentences.joined(separator: " ")
    }

    private var routeSentence: String? {
        guard refusal == nil, changesAnything else { return nil }
        let loss = routeLoss
        if loss.total > 0 {
            let positions = loss.total == 1 ? "1 recorded position" : "\(loss.total) recorded positions"
            return """
            \(positions) outside the corrected times will be deleted, and recorded mileage measured again \
            from what remains. You confirm before anything is deleted.
            """
        }
        return "No recorded position is deleted, and no route or mileage is added for any time gained."
    }

    private func timeText(_ date: Date) -> String {
        let sameDay = calendar.isDate(date, inSameDayAs: shift.startedAt)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return sameDay
            ? date.formatted(style.hour().minute())
            : date.formatted(style.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    private func spokenTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).month(.wide).day().hour().minute())
    }

    // MARK: Writing

    private var isConfirmingTrim: Binding<Bool> {
        Binding(get: { pendingTrim != nil }, set: { if !$0 { pendingTrim = nil } })
    }

    /// Confirms only when recorded positions would be deleted; any other valid
    /// correction saves at once.
    private func save() {
        saveError = nil
        let loss = routeLoss
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        if let prompt = ShiftTimeCorrectionPrompt.trimmingRoute(
            beforeStart: loss.beforeStart,
            afterEnd: loss.afterEnd,
            correctedStart: draftStart.formatted(style),
            correctedEnd: proposedEnd?.formatted(style)
        ) {
            pendingTrim = prompt
        } else {
            apply()
        }
    }

    private func apply() {
        pendingTrim = nil
        saveError = nil
        do {
            let correction = try service.correct(shift, start: draftStart, end: proposedEnd)
            if correction.isRunningShift { liveActivity?.reconcile() }
            dismiss()
        } catch {
            saveError = (error as? any LocalizedError)?.errorDescription ?? "Those times could not be saved."
        }
    }
}

#if DEBUG
#Preview("Correcting a finished shift's times") {
    PreviewSupport.shiftTimeCorrectionEditor()
}
#endif
