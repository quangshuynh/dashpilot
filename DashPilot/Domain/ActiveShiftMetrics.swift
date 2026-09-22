import Foundation

/// What DashPilot can honestly say about the shift the driver is in the middle
/// of, as of the moment it is read.
///
/// ## Why it is a separate type from ``ShiftMetrics``
///
/// ``ShiftMetrics`` answers "how did this shift go", and every question in it is
/// a question about a shift that has finished: it has an elapsed duration, a
/// final route and an amount the driver was paid. A shift in progress has none
/// of those, and the honest answer to most of them is a refusal rather than a
/// figure.
///
/// What a driver mid-shift actually has is a smaller set of facts that are true
/// *now*: how long they have worked, what the route has recorded so far, how
/// many deliveries are open. This type is that set, and it carries a
/// ``ShiftMetrics`` alongside them so the rates are not restated here — the
/// running shift's rates are the ones ``ShiftMetricsCalculator`` already derives
/// for an unfinished shift, which is to say every one of them is
/// ``ShiftRateUnavailability/shiftNotCompleted`` until it ends.
///
/// ## Nothing here is a final figure, and nothing is persisted
///
/// Every field is derived from the shift's own stored rows at the instant it was
/// built: the timestamps, the pause rows, the deliveries and the retained route.
/// Read again a second later it will differ, and that is what it is for. The
/// shift's *final* figures are measured once it ends, by the same calculations,
/// over the same rows.
///
/// ## Recorded, not driven
///
/// ``recordedDistance`` is what the retained route supports so far, with no
/// distance counted across a gap or across a pause. It is a floor on the miles
/// driven and grows only while positions are being accepted. See
/// ``RouteDistance`` and ``RouteQuality``.
nonisolated struct ActiveShiftMetrics: Equatable, Sendable {
    /// Where the shift is in its life. Never ``ShiftLifecycleState/ended``: a
    /// finished shift is described by ``ShiftMetrics`` instead.
    let lifecycleState: ShiftLifecycleState

    /// Start to now, pauses included.
    ///
    /// Carried because it is what the paused figure is subtracted from, not
    /// because the screen leads with it. A driver on a break watching an elapsed
    /// figure climb would be watching a number no rate they will ever see
    /// divides by.
    let elapsedDuration: TimeInterval

    /// How much of the shift so far the driver has had it paused, and how many
    /// times. ``ShiftPausedTime/none`` for a shift never paused, which is a
    /// measurement rather than a missing value.
    let pausedTime: ShiftPausedTime

    /// How much of the shift so far the driver recorded the vehicle as parked,
    /// and how many times. ``RouteSuspendedTime/none`` for a shift the driver
    /// never parked, which is a measurement rather than a missing value.
    ///
    /// **It is carried and never subtracted.** Walking into a shop to collect an
    /// order is working, so ``workingDuration`` is untouched by it and every
    /// rate derived from it keeps the denominator it had. What it explains is
    /// the route: capture is stopped for its whole length, so the recorded
    /// distance is lower and the route is partial, and this is the figure that
    /// says how much of that the driver asked for.
    let suspendedTime: RouteSuspendedTime

    /// Elapsed time so far less the time the shift has been paused.
    ///
    /// **The figure the screen leads with**, and the same definition the
    /// finished shift reports and every hourly rate divides by. While the shift
    /// is paused it does not grow, because the open pause grows at exactly the
    /// rate elapsed time does; that is a property of the subtraction rather than
    /// a rule written for the screen. See ``Shift/workingDuration(asOf:)``.
    let workingDuration: TimeInterval

    /// What the retained route has measured so far.
    ///
    /// Measured with **no shift window**, because an unfinished shift has none:
    /// its window is still growing, and measuring against the moment it is read
    /// would count every red light as an uncovered end. Gaps *between* recorded
    /// positions are counted exactly as they are for a finished shift, and a
    /// pause always produces one because resuming mints a new capture session.
    let recordedDistance: RouteDistance

    /// How many deliveries the shift has recorded, and how they stand.
    let deliverySummary: DeliverySummary

    /// The shift's rates, which for an unfinished shift are the reasons there
    /// are not any yet.
    ///
    /// Derived by ``ShiftMetricsCalculator`` from the shift's own facts, through
    /// the same adapter a finished shift uses. Nothing here relaxes a rate's
    /// data requirements because the figure would be nice to show: a rate that
    /// needs a finished shift is withheld, and the reason is stated.
    let rates: ShiftMetrics

    init(
        lifecycleState: ShiftLifecycleState,
        elapsedDuration: TimeInterval,
        pausedTime: ShiftPausedTime,
        suspendedTime: RouteSuspendedTime = .none,
        workingDuration: TimeInterval,
        recordedDistance: RouteDistance,
        deliverySummary: DeliverySummary,
        rates: ShiftMetrics
    ) {
        self.lifecycleState = lifecycleState
        self.elapsedDuration = elapsedDuration
        self.pausedTime = pausedTime
        self.suspendedTime = suspendedTime
        self.workingDuration = workingDuration
        self.recordedDistance = recordedDistance
        self.deliverySummary = deliverySummary
        self.rates = rates
    }

    /// Whether the driver has the shift paused right now.
    var isPaused: Bool { lifecycleState == .paused }

    /// Whether the driver has the vehicle recorded as parked right now.
    ///
    /// An ended or paused shift is never parked, which is the model's rule and
    /// is restated here only in the sense that ``lifecycleState`` is consulted
    /// alongside the rows.
    var isRouteSuspended: Bool {
        lifecycleState == .running && suspendedTime.isSuspended
    }

    /// What a glanceable surface says while the vehicle is recorded as parked,
    /// or `nil` when it is not.
    ///
    /// Short enough for a Lock Screen and careful about the two facts that must
    /// not be confused: the **route** is not recording, and the **shift** still
    /// is.
    var routeSuspendedNotice: String? {
        isRouteSuspended ? "Parked · route not recording" : nil
    }

    /// The same fact spoken, where a middle dot is punctuation rather than a
    /// word.
    var spokenRouteSuspendedNotice: String? {
        guard isRouteSuspended else { return nil }
        return "Parked. Your route is not being recorded, and your shift is still running."
    }

    /// The vocabulary for what the route can be said to show.
    var routeQuality: RouteQuality { RouteQuality(recordedDistance, suspendedTime: suspendedTime) }

    /// The amount recorded for the shift, or `nil` when none is.
    ///
    /// Always `nil` in practice while the shift runs: ``Shift/setGrossEarnings(_:)``
    /// refuses an amount on a shift that has not finished, because a shift still
    /// being worked has not finished paying and a monetary text field is not an
    /// interaction to ask for from a moving car. It is read from the shift
    /// rather than assumed, so the screen shows an amount if one is ever there
    /// and never fills one in.
    var grossEarnings: Money? { rates.grossEarnings }

    // MARK: What the screen says

    /// The mileage line: `"4.5 mi recorded"`, or why there is not one.
    func mileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        routeQuality.mileageStatement(locale: locale)
    }

    /// The same line as VoiceOver should hear it, with the partial-route claim
    /// folded in as a sentence rather than left as a two-word marker.
    func spokenMileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        routeQuality.spokenMileageStatement(locale: locale)
    }

    /// The two-word marker shown beside the mileage when the route so far is
    /// known to cover less than the shift, or `nil` when no gap was detected.
    var partialMarker: String? { routeQuality.partialMarker }

    /// The whole mileage line as the running shift's panel writes it:
    /// `"4.5 mi recorded · partial route"`.
    ///
    /// The marker travels with the figure rather than being left to a caller to
    /// remember, because a recorded mileage shown without it is the one claim
    /// this app must not make. A route with no gap detected carries nothing
    /// extra: "no gap detected" is not the same statement as "complete", and the
    /// place that difference is explained is the finished shift's own screen.
    func mileageLine(locale: Locale = .autoupdatingCurrent) -> String {
        guard let partialMarker else { return mileageStatement(locale: locale) }
        return "\(mileageStatement(locale: locale)) · \(partialMarker)"
    }

    /// What the capture has looked like so far: `"2 capture segments · 1 capture gap"`,
    /// or `nil` when there is no measured route to describe.
    ///
    /// The compact form of the two statements the completed-shift screen gives a
    /// row each. A running shift's panel is the screen a driver glances at from
    /// a cradle, so the counts share a line and the explanation of what they
    /// mean stays on the detail screen.
    var captureStatement: String? {
        guard
            let segments = routeQuality.segmentStatement,
            let gaps = routeQuality.gapStatement
        else {
            return nil
        }
        return "\(segments) · \(gaps)"
    }

    /// What the shift's deliveries are doing: `"2 deliveries in progress · 3 completed"`.
    ///
    /// In-progress first, because that is what a driver mid-shift is being asked
    /// to keep track of. Cancelled deliveries are counted separately and never
    /// folded into the completed total, exactly as ``DeliverySummary`` counts
    /// them for a finished shift.
    var deliveryStatement: String {
        var parts = [deliverySummary.inProgressStatement]
        if deliverySummary.completed > 0 {
            parts.append("\(deliverySummary.completed) completed")
        }
        if deliverySummary.cancelled > 0 {
            parts.append("\(deliverySummary.cancelled) cancelled")
        }
        return parts.joined(separator: " · ")
    }

    /// The same facts as sentences, for VoiceOver, where the separator is not
    /// spoken and "1 completed" on its own says nothing about what was completed.
    var spokenDeliveryStatement: String {
        var parts = [deliverySummary.inProgressStatement]
        if deliverySummary.completed > 0 {
            parts.append("\(deliverySummary.completed) delivered")
        }
        if deliverySummary.cancelled > 0 {
            parts.append("\(deliverySummary.cancelled) cancelled")
        }
        return parts.joined(separator: ". ")
    }

    /// The one sentence saying why no rate is shown, or `nil` when at least one
    /// of them could be derived.
    ///
    /// The reason is taken from the shift's own rates rather than written here,
    /// so the running shift and the finished shift explain an absent figure in
    /// the same words. While a shift runs that sentence is always
    /// ``ShiftRateUnavailability/shiftNotCompleted``'s, because a rate whose
    /// numerator has not been recorded and whose denominator is still growing is
    /// not a rate yet.
    var rateNotice: String? {
        guard !rates.hasAnyRate else { return nil }
        return rates.grossPerWorkingHour.unavailability?.explanation
    }
}

extension Shift {
    /// This shift's live figures, as of `referenceDate`.
    ///
    /// The adapter between the model and the calculations, holding no rule of
    /// its own: working duration comes from ``Shift/workingDuration(asOf:)``,
    /// the rates from ``Shift/metrics(for:)``, the deliveries from
    /// ``Shift/deliverySummary``. Nothing is stored.
    ///
    /// `recordedDistance` is passed in rather than measured here, for the reason
    /// ``Shift/metrics(for:using:)`` takes it: measuring a route walks every
    /// position it holds, and a shift in progress is exactly the case where the
    /// caller should be extending a measurement rather than repeating one. See
    /// ``ActiveShiftMetricsService``.
    func activeMetrics(for recordedDistance: RouteDistance, asOf referenceDate: Date) -> ActiveShiftMetrics {
        ActiveShiftMetrics(
            lifecycleState: lifecycleState,
            elapsedDuration: elapsed(asOf: referenceDate),
            pausedTime: pausedTime(asOf: referenceDate),
            suspendedTime: suspendedTime(asOf: referenceDate),
            workingDuration: workingDuration(asOf: referenceDate),
            recordedDistance: recordedDistance,
            deliverySummary: deliverySummary,
            rates: metrics(for: recordedDistance)
        )
    }
}
