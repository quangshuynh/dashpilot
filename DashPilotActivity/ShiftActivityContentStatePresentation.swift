import Foundation

/// What the Lock Screen and the Dynamic Island draw from one snapshot.
///
/// Every member here is a *reading* of the facts the app put in the snapshot.
/// Nothing decides anything: no rule about when a shift may pause, no rule about
/// which delivery a step belongs to, no second opinion about what a route
/// measured. Those all live in the app, and what arrives here has already been
/// through them.
///
/// The wording is tested from the app's own test target, which compiles the same
/// source these extension surfaces do.
nonisolated extension ShiftActivityAttributes.ContentState {
    /// The instant the working clock counts from.
    ///
    /// **This is what keeps the surface off a per-second update cadence.**
    /// Working time grows at exactly the rate wall-clock time does while a shift
    /// runs, so a single anchor lets the system draw a clock that stays correct
    /// with no further updates at all. Pushing a new figure every second would
    /// be asking the system to redraw a number it can derive, once a second, for
    /// the length of a shift.
    var workingTimerAnchor: Date { asOf.addingTimeInterval(-workingDuration) }

    /// The range a counting-up timer is drawn over while the shift runs.
    ///
    /// Open ended on purpose. Any horizon short enough to write down is a
    /// horizon a forgotten shift can outlive, and a clock that silently stops is
    /// worse than one that keeps counting an unusually long day.
    var workingTimerRange: ClosedRange<Date> { workingTimerAnchor...Date.distantFuture }

    /// The working figure as a fixed string, for a shift that is paused.
    ///
    /// A paused shift's working time does not move, because the open pause grows
    /// exactly as fast as elapsed time, so it is drawn once rather than counted.
    ///
    /// The hour field is dropped below an hour **to match what the system's own
    /// timer draws** for the running shift. It is the one place this surface
    /// deviates from the app's panel, which always shows `0:00:51`, and the
    /// reason is that the two figures sit in the same place on the same card: a
    /// number that gains a leading `0:` at the moment the driver pauses reads as
    /// a different number rather than as the same one held still.
    var formattedWorkingTime: String {
        let duration = Duration.seconds(workingDuration)
        return workingDuration < 3_600
            ? duration.formatted(.time(pattern: .minuteSecond))
            : duration.formatted(.time(pattern: .hourMinuteSecond))
    }

    /// The working figure as VoiceOver should hear it.
    ///
    /// Spelled-out units, to the second, for the reason the app speaks a paused
    /// shift's figure to the second: a clock string is heard as punctuation, and
    /// a figure that is not changing is worth being told exactly.
    var spokenWorkingTime: String {
        Duration.seconds(workingDuration)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// `"Shift Paused"` or `"Shift in Progress"`, matching the app's own heading.
    var statusTitle: String { isPaused ? "Shift Paused" : "Shift in Progress" }

    /// A symbol for the state that does not rely on colour.
    var statusSymbolName: String { isPaused ? "pause.circle.fill" : "record.circle" }

    /// The mileage and the marker that qualifies it, on one line:
    /// `"4.5 mi recorded · partial route"`.
    ///
    /// The marker is joined here rather than left to each surface to remember,
    /// for the reason the app's panel joins it in one place: a recorded figure
    /// shown without it claims more than the route supports.
    var mileageLine: String {
        guard let partialRouteMarker else { return mileageStatement }
        return "\(mileageStatement) · \(partialRouteMarker)"
    }

    /// The same line as VoiceOver should hear it, with the marker spoken as a
    /// sentence rather than as a two-word fragment.
    var spokenMileageLine: String {
        guard partialRouteMarker != nil else { return mileageStatement }
        return "\(mileageStatement). Partial route: DashPilot was not recording for part of this shift."
    }

    /// How the deliveries stand: `"2 in progress · 5 delivered"`.
    ///
    /// Shorter than the app's own sentence, because the space is smaller. In
    /// progress comes first: it is what a driver mid-shift is being asked to
    /// keep track of.
    var deliveryLine: String {
        var parts = [Self.printedInProgress(activeDeliveryCount)]
        if completedDeliveryCount > 0 {
            parts.append("\(completedDeliveryCount) delivered")
        }
        return parts.joined(separator: " · ")
    }

    /// The same facts as sentences, for VoiceOver, where the separator is not
    /// spoken.
    var spokenDeliveryLine: String {
        var parts = [Self.spokenInProgress(activeDeliveryCount)]
        if completedDeliveryCount > 0 {
            parts.append("\(completedDeliveryCount) \(Self.noun(completedDeliveryCount)) delivered")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: How long each delivery has been open

    /// How many delivery timers the card draws before it stops adding lines.
    ///
    /// A presentation limit and nothing else: it decides how many rows fit, not
    /// which delivery matters. A Lock Screen card has a fixed height, and the
    /// controls sit **below** these lines, so an unbounded list would push the
    /// buttons a driver reaches for off the bottom of the card. Three covers
    /// every stack this work ordinarily produces; beyond it the count is stated
    /// rather than the lines drawn, because a dropped row that says nothing is
    /// the one outcome that would mislead.
    static var maximumDrawnDeliveryTimers: Int { 3 }

    /// The timers the card draws, in the order the shift accepted them.
    ///
    /// The order is the shift's own acceptance order, which is the order every
    /// other numbered surface in the app uses. It is an ordering rather than a
    /// ranking: nothing here says the first one is the delivery that matters.
    var drawnDeliveryTimers: [ShiftActivityDeliveryTimer] {
        Array(activeDeliveryTimers.prefix(Self.maximumDrawnDeliveryTimers))
    }

    /// How many open deliveries have no line of their own on the card.
    var undrawnDeliveryTimerCount: Int {
        max(0, activeDeliveryTimers.count - Self.maximumDrawnDeliveryTimers)
    }

    /// `"1 more also active"`, or `nil` when every open delivery has a line.
    ///
    /// Short, because it shares a card with the controls. It states a count and
    /// claims nothing about how long those deliveries have been running: the
    /// app is where their timers are.
    var undrawnDeliveryTimerNotice: String? {
        guard undrawnDeliveryTimerCount > 0 else { return nil }
        return "\(undrawnDeliveryTimerCount) more also active"
    }

    /// The same fact with the noun restored, because a listener has no line
    /// above it to read the subject from.
    var spokenUndrawnDeliveryTimerNotice: String? {
        guard undrawnDeliveryTimerCount > 0 else { return nil }
        let count = undrawnDeliveryTimerCount
        return "\(count) more \(Self.noun(count)) also active. Open DashPilot for their timers."
    }

    /// Each drawn timer as one frozen spoken sentence, for the one presentation
    /// with no live element of its own.
    ///
    /// Frozen at ``asOf``, exactly as ``spokenWorkingTime`` is, and for the same
    /// reason: ``spokenSummary`` is a single string handed to a glyph, and a
    /// string cannot count. Every surface that has room for an element draws the
    /// system's live timer instead.
    var spokenDeliveryTimerLines: [String] {
        drawnDeliveryTimers.map { $0.spokenElapsed(asOf: asOf) }
            + [spokenUndrawnDeliveryTimerNotice].compactMap { $0 }
    }

    /// The whole snapshot as one spoken description, for a surface that reads as
    /// a single element.
    var spokenSummary: String {
        var sentences = [statusTitle]
        sentences.append("\(spokenWorkingTime) worked so far")
        sentences.append(spokenMileageLine)
        sentences.append(spokenDeliveryLine)
        if let deliveryStatus { sentences.append(deliveryStatus) }
        sentences.append(contentsOf: spokenDeliveryTimerLines)
        return sentences.joined(separator: ". ")
    }

    /// Why no step is offered, or `nil` when the question does not arise.
    ///
    /// The app offers no step when two or more deliveries are open: there is no
    /// "the delivery" for one to belong to, and pausing and ending are both
    /// refused while any delivery is running. A card that has dropped the
    /// controls a driver was using a minute ago, with no explanation, reads as
    /// broken, so the refusal is said rather than left to be inferred. It is the
    /// short form of the sentence the spoken surface gives for the same refusal.
    ///
    /// Read from the counts rather than from `controls.isEmpty`, which is what
    /// it used to be. Start Delivery is offered on every running shift including
    /// this one, because it names no existing order, so the list is no longer
    /// empty in the state the sentence is about. The refusal it explains is
    /// unchanged: it is the *step* that is withheld.
    var controlNotice: String? {
        guard !isPaused, activeDeliveryCount > 1, !offersDeliveryStep else { return nil }
        return "Several deliveries are in progress. Open DashPilot to record a step."
    }

    /// Whether the card carries a step of one delivery in progress.
    private var offersDeliveryStep: Bool {
        controls.contains { if case .deliveryStep = $0 { true } else { false } }
    }

    /// The number a Dynamic Island's compact side can fit, and nothing else.
    ///
    /// Deliberately not a figure with a unit: at that size a mileage reading
    /// with `"recorded"` trimmed off it would be the exact claim this project
    /// refuses to make, so the compact form carries the count of open deliveries
    /// instead, which needs no qualifier to be true.
    var compactDeliveryCount: String { "\(activeDeliveryCount)" }

    /// `"No delivery in progress"` or `"2 in progress"`. The noun is dropped
    /// once there is a count, because the line it sits on has already said what
    /// is being counted.
    private static func printedInProgress(_ count: Int) -> String {
        count == 0 ? "No delivery in progress" : "\(count) in progress"
    }

    /// The same fact with the noun restored, because a listener has no line to
    /// read it from.
    private static func spokenInProgress(_ count: Int) -> String {
        count == 0 ? "No delivery in progress" : "\(count) \(noun(count)) in progress"
    }

    private static func noun(_ count: Int) -> String {
        count == 1 ? "delivery" : "deliveries"
    }
}
