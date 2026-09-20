import SwiftData
import SwiftUI

/// Correcting the times a finished delivery recorded.
///
/// ## What the driver is really changing
///
/// The instants this delivery **already records**, and every figure derived from
/// them. One picker per recorded event, and nothing else on the sheet: a stage
/// the delivery never recorded has no row here at all, because a control
/// offering to set a time for an arrival that never happened is an invitation to
/// invent one.
///
/// ## What it says before it writes anything
///
/// Three things, all of them above Save. What moves, which is how long the
/// delivery took, how long the pickup wait was, what it paid per recorded
/// delivery hour and how much of the shift was delivery active. What does not,
/// which is the route and the shift's recorded mileage, the consequence a
/// driver is least likely to have in mind, since moving a completion back by
/// twenty minutes sounds like it should take miles with it. And that nothing
/// cascades, so a time refused for colliding with another is corrected by
/// correcting that one too.
///
/// ## No confirmation, and that is a decision
///
/// The corrections in this app that raise an alert each **destroy** something:
/// an end moved earlier deletes recorded positions, and deleting a pause removes
/// a row. This deletes nothing, creates nothing, and leaves the delivery's
/// terminal outcome, its offer, its pickup place and every amount on it exactly
/// as they are. So it takes ``ShiftPauseEditor``'s shape instead: a draft, the
/// consequences stated on the sheet, and Save. Raising an alert over a
/// correction that destroys nothing is what teaches a driver to confirm without
/// reading.
///
/// ## A draft, applied on purpose
///
/// Nothing is written while the pickers move. **Cancel leaves the delivery
/// exactly as it was**, and the figures behind the sheet do not move until Save.
/// The whole draft is then judged at once and written at once: a refused save
/// leaves every original instant, not some of them.
///
/// ## Why it is refused rather than corrected
///
/// A draft the domain will not accept is **named and refused**, never quietly
/// clamped or nudged into the nearest acceptable instant, and never resolved by
/// moving a second timestamp out of the way. The sentence under the pickers is
/// the domain's own, written by ``DeliveryLifecycleError`` so that the refusal
/// the driver reads and the refusal the write would raise cannot drift apart.
///
/// ## The calendar is the environment's
///
/// The pickers take their calendar and time zone from the environment, and the
/// times printed here take the environment's locale, exactly as
/// ``ShiftEndCorrectionEditor`` and ``ShiftPauseEditor`` read them. **Nothing
/// here reaches for `Calendar.autoupdatingCurrent`.** What a picker produces is
/// an **instant**, so a delivery corrected across a daylight-saving change
/// measures the minutes that really passed rather than the ones the wall clock
/// appears to show.
struct DeliveryTimeCorrectionEditor: View {
    /// The finished delivery whose recorded times are being corrected, named the
    /// way every other control on its card names it.
    let numbered: NumberedDelivery

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    /// The times the sheet will write, seeded from the times the delivery
    /// records.
    ///
    /// A ``DeliveryLifecycleRecord`` rather than five optional `Date` properties,
    /// so which stages exist is carried by the draft itself and a picker cannot
    /// bring one into existence: ``DeliveryLifecycleRecord/replacing(_:with:)``
    /// leaves an unrecorded stage unrecorded.
    @State private var draft: DeliveryLifecycleRecord

    /// What the store said when a save was refused, kept on the sheet so the
    /// driver reads it beside the times that caused it.
    @State private var saveError: String?

    init(numbered: NumberedDelivery) {
        self.numbered = numbered
        // Opens on the times the delivery records, which is deliberately not a
        // suggestion: they are the facts being corrected, and a driver who opens
        // this by mistake and saves writes back exactly what was already there.
        // Nothing here proposes when the work really happened, because nothing
        // in DashPilot observed it.
        _draft = State(initialValue: DeliveryLifecycleRecord(numbered.delivery))
    }

    private var delivery: Delivery { numbered.delivery }

    var body: some View {
        NavigationStack {
            Form {
                timesSection
                consequenceSection
            }
            .navigationTitle("Correct Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel, keep the times \(numbered.title) recorded")
                        .accessibilityIdentifier("deliveryTimeCorrectionCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(refusal != nil)
                        .accessibilityLabel("Save the corrected times for \(numbered.title)")
                        .accessibilityIdentifier("deliveryTimeCorrectionSaveButton")
                }
            }
        }
    }

    // MARK: Sections

    /// One picker per recorded event, in lifecycle order.
    ///
    /// ``DeliveryLifecycleRecord/recordedEvents`` decides which rows exist, so a
    /// delivery cancelled before it reached a pickup shows three pickers and a
    /// delivered one shows four. The stages in the draft never change, which is
    /// why the list is stable while the times move.
    private var timesSection: some View {
        Section {
            ForEach(draft.recordedEvents, id: \.event) { recorded in
                DatePicker(
                    recorded.event.historyDescription,
                    selection: binding(for: recorded.event),
                    in: selectableRange,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("deliveryTimeCorrectionPicker.\(recorded.event.rawValue)")
            }
        } header: {
            Text("Recorded Times")
        } footer: {
            Text(DeliveryTimeCorrectionStatement.eachTimeIsCorrectedExplicitly)
        }
    }

    /// What the chosen times would record, or why they record nothing.
    @ViewBuilder
    private var consequenceSection: some View {
        Section {
            if let refusal {
                let sentence = DeliveryLifecycleError.invalidTimeCorrection(refusal).errorDescription
                    ?? "Those times cannot be recorded for this delivery."
                Label(sentence, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    // One element carrying the sentence rather than a glyph
                    // called "Warning" beside it: the icon is decoration, the
                    // refusal is the whole of what has to be read out, and the
                    // colour is never the only thing carrying it.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(sentence)
                    .accessibilityIdentifier("deliveryTimeCorrectionRefusal")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(derivedFigures) { figure in
                        LabeledContent(figure.label) {
                            Text(figure.value).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    Text(DeliveryTimeCorrectionStatement.derivedFiguresMove)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenSummary)
                .accessibilityIdentifier("deliveryTimeCorrectionSummary")

                // The one consequence a driver cannot see anywhere else on this
                // sheet, and the one they are most likely to assume wrongly.
                Label(DeliveryTimeCorrectionStatement.routeIsNotChanged, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(DeliveryTimeCorrectionStatement.routeIsNotChanged)
                    .accessibilityIdentifier("deliveryTimeCorrectionRouteNotice")
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(saveError)
                    .accessibilityIdentifier("deliveryTimeCorrectionSaveError")
            }
        } header: {
            Text("Corrected \(numbered.title)")
        } footer: {
            Text(DeliveryTimeCorrectionStatement.recordIsOtherwiseUnchanged)
        }
    }

    // MARK: Derived values

    /// The figures the corrected times would produce, each derived by the app's
    /// own calculation over the draft rather than by a second rule.
    ///
    /// Only the ones that exist. A cancelled delivery has no completed duration
    /// and no rate, a delivery that never recorded a pickup has no wait, and a
    /// row saying `Not recorded` for each of them would invite a driver to look
    /// for a figure the data cannot support.
    private var derivedFigures: [DraftFigure] {
        var figures: [DraftFigure] = []
        if let wait = draft.pickupWait {
            figures.append(
                DraftFigure(
                    label: "Waited at pickup",
                    value: DurationText.short(wait),
                    spoken: "Waited at pickup \(DurationText.spoken(wait)), for \(numbered.title)"
                )
            )
        }
        if let duration = draft.completedDuration {
            figures.append(
                DraftFigure(
                    label: "Accepted to delivered",
                    value: DurationText.short(duration),
                    spoken: "Accepted to delivered \(DurationText.spoken(duration)), for \(numbered.title)"
                )
            )
            if let rate = draftRate {
                let amount = rate.formatted(locale: locale)
                figures.append(
                    DraftFigure(
                        label: "Per delivery hour",
                        value: amount,
                        // The denominator is named in full, because "per hour"
                        // alone would be heard as a wage.
                        spoken: numbered.spokenDeliveryHourRate(amount)
                    )
                )
            }
        }
        return figures
    }

    /// What this delivery would earn per hour of its corrected lifecycle.
    ///
    /// The numerator is the delivery's **existing** effective earnings, because
    /// this correction touches no amount, and the arithmetic is
    /// ``ShiftMetricsCalculator/grossPerHour(of:over:)``, the one definition of
    /// an amount per hour in the app, and the one
    /// ``Delivery/effectiveEarningsPerDeliveryHour`` will use to report the same
    /// figure once the draft is saved.
    private var draftRate: Money? {
        guard let duration = draft.completedDuration,
              let earnings = delivery.effectiveEarnings.amount
        else { return nil }
        return ShiftMetricsCalculator.grossPerHour(of: earnings, over: duration)
    }

    /// The figures read as sentences, because a list of unattached durations is
    /// unintelligible by ear, and named for their delivery like every other
    /// spoken figure in a history of several.
    private var spokenSummary: String {
        var sentences = derivedFigures.map(\.spoken)
        if sentences.isEmpty {
            sentences.append("\(numbered.title) records no duration these times would change")
        }
        sentences.append(DeliveryTimeCorrectionStatement.derivedFiguresMove)
        return sentences.joined(separator: ". ")
    }

    /// The stretch every picker may choose within: the shift's own window.
    ///
    /// Bounded by the two instants no recorded event may fall outside, so those
    /// two refusals are a backstop rather than the ordinary way a driver meets
    /// the rule. The ordering rules depend on the other pickers and cannot be
    /// expressed as a bound at all, so they are stated in the footer and refused
    /// below.
    ///
    /// A reversed range traps, so the upper bound is never allowed below the
    /// lower one. Falls back to the delivery's own recorded span for a shift
    /// with no window, which is a store the app cannot produce and which the
    /// domain refuses anyway.
    private var selectableRange: ClosedRange<Date> {
        guard let window = delivery.shift?.completedWindow else {
            let recorded = DeliveryLifecycleRecord(delivery).recordedEvents.map(\.occurredAt)
            let lower = recorded.min() ?? delivery.acceptedAt
            return lower...max(lower, recorded.max() ?? lower)
        }
        return window.lowerBound...max(window.lowerBound, window.upperBound)
    }

    // MARK: Writing

    /// One picker's binding, which reads the draft and writes through
    /// ``DeliveryLifecycleRecord/replacing(_:with:)``.
    ///
    /// The getter falls back to the delivery's own instant for a stage the draft
    /// somehow does not record, which the section's own `ForEach` makes
    /// unreachable: it is drawn from the draft's recorded stages, and those
    /// never change while the sheet is open.
    private func binding(for stage: DeliveryState) -> Binding<Date> {
        Binding(
            get: { draft.instant(of: stage) ?? delivery.acceptedAt },
            set: { draft = draft.replacing(stage, with: $0) }
        )
    }

    /// Why the current draft would be refused, or `nil` if it would be accepted.
    ///
    /// Asked of the service, which asks the domain, so the sentence on screen and
    /// the rule the write consults are the same thing rather than two opinions
    /// about it.
    private var refusal: DeliveryTimeCorrectionRefusal? {
        DeliveryService(context: modelContext).timeCorrectionRefusal(on: delivery, to: draft)
    }

    private func save() {
        saveError = nil
        do {
            try DeliveryService(context: modelContext).correctRecordedTimes(delivery, to: draft)
            dismiss()
        } catch {
            // Named on the sheet rather than swallowed, and the sheet stays open
            // so the driver still has the times they chose.
            saveError = (error as? any LocalizedError)?.errorDescription
                ?? "Those times could not be saved."
        }
    }
}

/// One figure the corrected times would produce, with what it is called, what it
/// says, and what VoiceOver hears instead.
///
/// The spoken form is carried rather than derived from the label, so a listener
/// hears a sentence naming its delivery and its denominator rather than a bare
/// figure, and adding a figure means writing both forms at once.
private struct DraftFigure: Identifiable {
    let label: String
    let value: String
    let spoken: String

    var id: String { label }
}

#if DEBUG
#Preview("Correcting a delivered delivery's times") {
    PreviewSupport.deliveryTimeCorrectionEditor()
}
#endif
