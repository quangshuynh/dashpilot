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
    /// A paused shift's working time does not move — the open pause grows
    /// exactly as fast as elapsed time — so it is drawn once rather than
    /// counted. The clock pattern is the one the app's own panel uses for the
    /// same figure.
    var formattedWorkingTime: String {
        Duration.seconds(workingDuration).formatted(.time(pattern: .hourMinuteSecond))
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

    /// The whole snapshot as one spoken description, for a surface that reads as
    /// a single element.
    var spokenSummary: String {
        var sentences = [statusTitle]
        sentences.append("\(formattedWorkingTime) worked so far")
        sentences.append(spokenMileageLine)
        sentences.append(spokenDeliveryLine)
        if let deliveryStatus { sentences.append(deliveryStatus) }
        return sentences.joined(separator: ". ")
    }

    /// Why there are no controls, or `nil` when there are some.
    ///
    /// The app offers nothing when two or more deliveries are open: there is no
    /// "the delivery" for a step to belong to, and pausing and ending are both
    /// refused while any delivery is running. A surface with no buttons and no
    /// explanation reads as broken, so the refusal is said rather than left to be
    /// inferred. It is the short form of the sentence the spoken surface gives
    /// for the same refusal.
    var controlNotice: String? {
        guard controls.isEmpty else { return nil }
        return "Several deliveries are in progress. Open DashPilot to record a step."
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
