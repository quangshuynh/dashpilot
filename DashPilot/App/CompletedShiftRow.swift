import SwiftData
import SwiftUI

/// One finished shift in history: what shift it was, and roughly how it went.
///
/// In a file of its own, and not private, because two screens draw it now:
/// the current week on ``RootView`` and every week before it on
/// ``OlderHistoryWeeksView``. A row that looked slightly different depending
/// on which week it was in would be the interface disagreeing with itself,
/// so there is one row and both lists use it.
///
/// Deliberately three lines and no controls. The row's job is to be scanned and
/// tapped; everything it used to carry inline — the second rate, the route's
/// segments and gaps, the earnings editor, and now deletion — belongs to
/// ``CompletedShiftDetailView``, which has the room to explain it.
///
/// What survives here is what a driver picking a shift out of a list needs:
/// when it ran, how long it lasted, what it paid, what its route recorded, and
/// the one rate that answers "how did this shift go" — gross earnings per shift
/// hour. The per-recorded-mile rate needs its denominator explained to be read
/// correctly, and that explanation is a detail-screen thing.
struct CompletedShiftRow: View {
    let shift: Shift

    /// Measured when the row appears rather than inside `body`.
    ///
    /// A shift's route can hold thousands of positions, and a view's body is
    /// re-evaluated whenever the list redraws. Nothing is cached in the store —
    /// the number is still derived from the route every time the row is built.
    @State private var recordedDistance: RouteDistance?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.sm) {
            heading
            Text(schedule)
                .dashFont(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary {
                Text(summary)
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    // Wrap rather than truncate. The first thing a truncation
                    // takes is the end of "recorded", which is the word that
                    // makes the mileage honest.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DashSpacing.sm)
        .task(id: shift.id) { recordedDistance = shift.recordedDistance() }
        // One element so VoiceOver reads the shift as a shift rather than three
        // unrelated fragments, with an explicit label because the abbreviations
        // that read well — "mi", "/hr", "·" — are poor to hear.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The date, with the recorded amount alongside it — or under it once the
    /// text is large enough that two items cannot share a line without one of
    /// them being truncated. A shortened date and a shortened amount are both
    /// worse than a second line.
    @ViewBuilder
    private var heading: some View {
        let date = Text(shift.startedAt, format: .dateTime.weekday(.abbreviated).month().day())
            .dashFont(.emphasis)

        if dynamicTypeSize.isAccessibilitySize {
            date
            recordedEarnings
        } else {
            HStack(alignment: .firstTextBaseline) {
                date
                Spacer(minLength: DashSpacing.md)
                recordedEarnings
            }
        }
    }

    /// The amount, and only the amount. The rate derived from it is a separate
    /// line, in a smaller style, so the figure the driver actually recorded is
    /// never confused with the one DashPilot worked out.
    @ViewBuilder
    private var recordedEarnings: some View {
        if let earnings = shift.grossEarnings {
            Text(earnings.formatted(locale: locale))
                .dashFont(.emphasis)
                .monospacedDigit()
        }
    }

    /// The third line: what the route recorded, and the shift's hourly rate.
    ///
    /// Both are omitted when they do not exist. An unavailable rate leaves
    /// nothing behind — no dash, no `$0.00` — because a shift with no amount
    /// recorded and a shift that paid nothing are different facts; the detail
    /// screen is where the difference is explained.
    private var summary: String? {
        guard let quality else { return nil }
        var parts = [quality.mileageStatement(locale: locale)]
        if let marker = quality.partialMarker {
            parts.append(marker)
        }
        if let hourly = metrics?.grossPerWorkingHour.amount {
            parts.append("\(hourly.formatted(locale: locale))/hr")
        }
        return parts.joined(separator: " · ")
    }

    /// When the shift ran and how long it was worked.
    ///
    /// The duration here is the **working** one, because it is the figure the
    /// rate on the line below divides by; a row showing elapsed time beside a
    /// per-working-hour rate would not multiply out. A shift that was paused
    /// says so, so the shorter figure is not read as a mistake.
    private var schedule: String {
        let started = shift.startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt = shift.endedAt, let working = shift.completedWorkingDuration else {
            return started
        }
        let ended = endedAt.formatted(date: .omitted, time: .shortened)
        var line = "\(started) – \(ended) · \(DurationText.short(working))"
        if pauseCount > 0 {
            line += pauseCount == 1 ? " · 1 pause" : " · \(pauseCount) pauses"
        }
        return line
    }

    /// How many stretches the driver paused this shift for.
    private var pauseCount: Int { shift.completedPausedTime?.intervalCount ?? 0 }

    /// What VoiceOver says instead of the abbreviations.
    ///
    /// Sentences rather than separators, spelled-out miles, and the partial
    /// route stated as a claim rather than as a two-word marker — the marker is
    /// legible beside the figure it qualifies and unintelligible on its own.
    private var accessibilityLabel: String {
        var sentences = [shift.startedAt.formatted(date: .complete, time: .omitted)]

        if let endedAt = shift.endedAt, let working = shift.completedWorkingDuration {
            let started = shift.startedAt.formatted(date: .omitted, time: .shortened)
            let ended = endedAt.formatted(date: .omitted, time: .shortened)
            sentences.append("\(started) to \(ended)")
            sentences.append("\(DurationText.spoken(working)) worked")
            if let paused = shift.completedPausedTime, paused.hasPauses {
                sentences.append("\(DurationText.spoken(paused.duration)) paused")
            }
        }

        if let earnings = shift.grossEarnings {
            sentences.append("\(earnings.formatted(locale: locale)) gross earnings recorded")
        } else {
            sentences.append("No earnings recorded")
        }

        if let quality {
            sentences.append(quality.spokenMileageStatement(locale: locale))
        }

        if let hourly = metrics?.grossPerWorkingHour.amount {
            sentences.append("\(hourly.formatted(locale: locale)) gross earnings per working hour")
        }

        return sentences.joined(separator: ". ")
    }

    private var quality: RouteQuality? {
        // The row shows the figure and the partial marker, and the marker's
        // wording changes when the driver parked. The detail screen behind it is
        // where the count and the duration are stated.
        recordedDistance.map { RouteQuality($0, suspendedTime: shift.completedSuspendedTime ?? .none) }
    }

    /// The rates this shift can support, derived from the amount recorded on it
    /// and the distance measured above.
    ///
    /// Deriving them here rather than in `.task` is deliberate: the expensive
    /// part is measuring the route, which happens once, and the rates are two
    /// divisions over the result. Recomputing them with the body is what keeps
    /// them correct the moment the driver adds, changes or removes an amount.
    /// Nothing is calculated in this view — ``ShiftMetricsCalculator`` owns
    /// every rule, including which rates exist at all.
    private var metrics: ShiftMetrics? {
        recordedDistance.map { shift.metrics(for: $0) }
    }
}
