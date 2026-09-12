import OSLog
import SwiftData
import SwiftUI

/// The shift in progress: whether it is running or paused, how long it has been
/// worked, what its route has recorded so far, what its deliveries are doing,
/// and the one or two lifecycle controls that apply.
///
/// ## What it is for
///
/// A live reading of a shift, not a preview of the shift's final report. Every
/// figure on it is true at the moment it is read and is derived from the same
/// rows and the same calculations the finished shift is reported with; nothing
/// is estimated forward, nothing is projected, and a figure whose data
/// requirements are not met is withheld with the reason rather than filled in.
/// See ``ActiveShiftMetrics``.
///
/// ## The three states
///
/// The three states a shift can be in are kept visually distinct rather than
/// distinguished by a button title. A driver glancing at the phone in a cradle
/// has to be able to tell a running shift from a paused one without reading:
/// running is a red recording label with a ticking figure, paused is an orange
/// pause label with a figure that does not move, and ended is not this screen at
/// all.
///
/// ## What it costs
///
/// The route is measured **incrementally**. The panel holds an open
/// ``ActiveRouteMeasurement`` and extends it with the positions recorded since
/// the last reading, rather than walking the whole route again; see
/// ``refreshInterval`` for the cadence and ``ActiveShiftRouteService`` for the
/// queries. Nothing derived is written to the store.
struct ActiveShiftPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale

    let shift: Shift
    let captureState: RouteCaptureState
    let pause: () -> Void
    let resume: () -> Void
    let end: () -> Void

    /// How often the stored route is read again while the shift is running.
    ///
    /// Not a redraw interval: the working figure ticks once a second on its own
    /// timeline, and this is only how often the *store* is asked whether the
    /// route has grown. Two seconds is under the interval between flushes of the
    /// capture batch, so a driver never waits on this for a number that already
    /// exists, and it is far longer than the reading costs.
    ///
    /// The reading is a count and, when the count moved, a fetch of the rows
    /// after the last one measured. Measured on the simulator against a stored
    /// route of 8,000 positions, that costs 1.1 ms when nothing has arrived and
    /// 2.3 ms when four positions have, and it barely moves with the length of
    /// the route. Measuring the whole route instead costs **247 ms** at the same
    /// length and grows with it, which is the reason this panel does not simply
    /// call ``Shift/recordedDistance(using:)`` in its body: a quarter of a second
    /// on the main actor, repeated for every reason a body is re-evaluated,
    /// would stall the one screen a driver looks at while driving. The figures
    /// are in `context.md`.
    private static let refreshInterval: TimeInterval = 2

    /// The open measurement of this shift's route.
    ///
    /// Held for as long as the panel is on screen and thrown away with it. It is
    /// a faster reading of stored rows, never a stored figure: when the shift
    /// ends it is discarded, and the shift's own history row measures the route
    /// from scratch.
    @State private var routeMeasurement: ActiveRouteMeasurement?

    private var isPaused: Bool { shift.isPaused }

    /// Everything the panel states about the shift, as of now.
    ///
    /// `nil` until the route has been read once, which is what keeps the panel
    /// from claiming "no route recorded" in the moment before it has looked.
    /// Nothing is calculated here: ``Shift/activeMetrics(for:asOf:)`` is the
    /// adapter, and the rules are the domain's.
    private var metrics: ActiveShiftMetrics? {
        routeMeasurement.map { shift.activeMetrics(for: $0.recordedDistance, asOf: .now) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                isPaused ? ShiftLifecycleState.paused.title : ShiftLifecycleState.running.title,
                systemImage: isPaused ? "pause.circle.fill" : "record.circle"
            )
            .font(.headline)
            .foregroundStyle(isPaused ? .orange : .red)
            .accessibilityIdentifier(isPaused ? "pausedShiftStatus" : "activeShiftStatus")

            workingTime

            LabeledContent("Started") {
                Text(shift.startedAt, format: .dateTime.hour().minute())
            }
            .font(.subheadline)

            if let pausedAt = shift.openPause?.startedAt {
                LabeledContent("Paused") {
                    Text(pausedAt, format: .dateTime.hour().minute())
                }
                .font(.subheadline)
                .accessibilityIdentifier("pausedAtTime")
            }

            if let metrics {
                recordedMileage(metrics)
                deliveries(metrics)
                earnings(metrics)
            }

            RouteCaptureStatusView(state: captureState)

            controls
        }
        .padding(.vertical, 8)
        // Reading the store on a cadence rather than with the body. A body is
        // re-evaluated for reasons that have nothing to do with the route — a
        // clock tick, a sibling row, a scroll — and measuring a route on each of
        // them would be work proportional to the length of the shift, paid for
        // nothing.
        .task(id: shift.id) {
            routeMeasurement = nil
            measureRoute()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard !Task.isCancelled else { return }
                // A paused shift records nothing, so there is nothing to read.
                // Resuming is caught by the lifecycle change below rather than
                // by this loop noticing eventually.
                if shift.lifecycleState == .running { measureRoute() }
            }
        }
        // Pausing flushes the positions captured up to the tap, and ending a
        // pause opens a new capture session. Both change what the figure should
        // say now rather than in a couple of seconds.
        .onChange(of: shift.lifecycleState) { _, _ in measureRoute() }
    }

    /// Extends the route measurement with whatever the store has gained.
    ///
    /// A store that cannot be read leaves the previous figure standing: a route
    /// that could not be read is not a route of no miles, and replacing a real
    /// figure with "no route recorded" because one query failed would be exactly
    /// the invention this app refuses elsewhere.
    private func measureRoute() {
        do {
            routeMeasurement = try ActiveShiftRouteService(context: modelContext)
                .measurement(extending: routeMeasurement, of: shift)
        } catch {
            AppLog.routeCapture.error("Could not read the running shift's route: \(error)")
        }
    }

    /// The working figure, ticking only while the shift is actually running.
    ///
    /// While paused it is rendered once rather than on a timeline. The
    /// subtraction already holds it still, because the open pause grows exactly
    /// as fast as elapsed time, so a per-second refresh would redraw an
    /// unchanged number every second for as long as the driver is on their
    /// break.
    @ViewBuilder
    private var workingTime: some View {
        if isPaused {
            WorkingTimeLabel(working: shift.workingDuration(asOf: .now), isPaused: true)
        } else {
            // Derived from the stored timestamps on every tick and never stored,
            // so it cannot drift away from the recorded times.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                WorkingTimeLabel(working: shift.workingDuration(asOf: context.date), isPaused: false)
            }
        }
    }

    /// What the route has recorded so far, and what qualifies it.
    ///
    /// The word "recorded" is part of the figure rather than a caption beside
    /// it, and the partial marker travels with it, because this is the number a
    /// driver is most likely to read as "miles I drove". Both come from
    /// ``RouteQuality`` through ``ActiveShiftMetrics``, so this panel and the
    /// finished shift's screen cannot drift into saying different things about
    /// the same route.
    ///
    /// The segment and gap counts sit under it in caption type. They are what
    /// makes the partiality concrete without the panel having to explain it: the
    /// sentence that does explain it is on the shift's own screen, and a driver
    /// in a cradle is not the audience for a paragraph.
    private func recordedMileage(_ metrics: ActiveShiftMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metrics.mileageLine(locale: locale))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            if let capture = metrics.captureStatement {
                Text(capture)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recorded mileage")
        // The spoken form folds the partial-route claim into a sentence: the
        // two-word marker is legible beside the figure and unintelligible heard
        // on its own.
        .accessibilityValue(
            [metrics.spokenMileageStatement(locale: locale), metrics.captureStatement]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
        .accessibilityIdentifier("liveRecordedMileage")
    }

    /// How many deliveries are open, and how many the shift has finished.
    private func deliveries(_ metrics: ActiveShiftMetrics) -> some View {
        Text(metrics.deliveryStatement)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Deliveries")
            .accessibilityValue(metrics.spokenDeliveryStatement)
            .accessibilityIdentifier("liveDeliveryCounts")
    }

    /// The amount recorded for the shift and the rates derived from it, or the
    /// one sentence saying why there are none yet.
    ///
    /// Every branch here is the existing rule, not a relaxed one. A shift's
    /// gross earnings cannot be recorded until it has finished, so in practice a
    /// running shift shows the sentence; the figures are rendered from
    /// ``ShiftMetrics`` all the same, so that the panel states whatever the data
    /// actually supports rather than a hard-coded absence. Nothing is inferred
    /// from the amounts recorded against individual deliveries: those are a
    /// separate fact, and adding them up would read every delivery with no
    /// amount as one that paid nothing.
    @ViewBuilder
    private func earnings(_ metrics: ActiveShiftMetrics) -> some View {
        if let gross = metrics.grossEarnings {
            LabeledContent("Recorded") {
                Text(gross.formatted(locale: locale)).monospacedDigit()
            }
            .font(.subheadline)
            .accessibilityLabel("Recorded gross earnings")
            .accessibilityIdentifier("liveRecordedGross")
        }

        rateRow("Per working hour", spokenAs: "gross earnings per working hour", rate: metrics.rates.grossPerWorkingHour)
        rateRow(
            "Per active delivery hour",
            spokenAs: "gross earnings per active delivery hour",
            rate: metrics.rates.grossPerDeliveryActiveHour
        )
        rateRow(
            "Per recorded mile",
            spokenAs: "gross earnings per recorded mile",
            rate: metrics.rates.grossPerRecordedMile
        )

        if let notice = metrics.rateNotice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("liveRateNotice")
        }
    }

    /// One rate, and only when there is one.
    ///
    /// An unavailable rate leaves nothing behind — no dash, no `$0.00` — because
    /// a rate that could not be derived and a rate of zero are different facts.
    /// The reason is said once, below, rather than three times.
    @ViewBuilder
    private func rateRow(_ title: String, spokenAs spokenTitle: String, rate: ShiftRate) -> some View {
        if let amount = rate.amount {
            LabeledContent(title) {
                Text(amount.formatted(locale: locale)).monospacedDigit()
            }
            .font(.subheadline)
            .accessibilityLabel(spokenTitle)
        }
    }

    /// Pause or Resume, and End.
    ///
    /// Resume is the prominent control on a paused shift, because it is the one
    /// the driver came back to the app to press. Pause is bordered on a running
    /// shift for the reason End is: the prominent control during a shift is the
    /// delivery action below, which is tapped many times a shift.
    @ViewBuilder
    private var controls: some View {
        if isPaused {
            Button(action: resume) {
                Text("Resume Shift")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("resumeShiftButton")
        } else {
            Button(action: pause) {
                Text("Pause Shift")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("pauseShiftButton")
        }

        // Bordered rather than prominent: the prominent control during a
        // shift is the delivery action just below, which is tapped many
        // times a shift, while this one is tapped once. Emphasising the
        // rarer, harder-to-undo button over the frequent one is how a
        // driver ends a shift by mistake. It stays available while paused:
        // a driver who has finished has finished, and making them resume a
        // shift they are not working in order to end it would record work
        // that did not happen.
        Button(action: end) {
            Text("End Shift")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
        .accessibilityIdentifier("endShiftButton")
    }
}

/// The big figure on a shift in progress: how long it has been **worked**.
///
/// Working time rather than elapsed time, because that is the figure every rate
/// the shift will produce divides by, and a driver watching one number during
/// the shift and reading a different one afterwards would have no way to tell
/// which was wrong.
struct WorkingTimeLabel: View {
    let working: TimeInterval
    let isPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(duration.formatted(.time(pattern: .hourMinuteSecond)))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isPaused ? .secondary : .primary)

            Text(isPaused ? "Worked so far · paused" : "Worked so far")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workingTime")
        .accessibilityLabel(isPaused ? "Working time, paused" : "Working time")
        .accessibilityValue(spokenDuration)
    }

    private var duration: Duration { .seconds(working) }

    /// The figure as VoiceOver hears it.
    ///
    /// To the minute while the shift runs, because a per-second read-out of a
    /// number that changes every second is noise. To the **second** while it is
    /// paused, for the same reason: the figure does not change, so it is not
    /// re-announced, and a driver asking what they have worked at the moment
    /// they stopped should be told exactly rather than to the nearest minute.
    private var spokenDuration: String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = isPaused
            ? [.hours, .minutes, .seconds]
            : [.hours, .minutes]
        return duration.formatted(.units(allowed: allowed, width: .wide))
    }
}
