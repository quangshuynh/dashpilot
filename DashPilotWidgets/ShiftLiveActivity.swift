import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The shift in progress, on the Lock Screen and in the Dynamic Island.
///
/// ## It draws, and that is all it does
///
/// Every value below comes out of ``ShiftActivityAttributes/ContentState``,
/// which the app derived from its store. This file contains no rule about when a
/// shift may pause, which delivery a step belongs to, what a route measured or
/// what any of it means. A button runs the app's own lifecycle service, in the
/// app's own process, and is refused there by the same rule that refuses the
/// button inside the app.
///
/// ## What it never shows
///
/// No money in any form, no rate, no recommendation, no goal, no address, no
/// pickup place, no coordinate, no customer. A Lock Screen is read by whoever is
/// standing next to the phone.
struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            ShiftActivityLockScreenView(state: context.state)
                // The one tint on the surface. The card is otherwise the
                // system's, because a Lock Screen in a cradle in daylight is not
                // the place to spend contrast on decoration.
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            dynamicIsland(for: context.state)
        }
    }

    /// The expanded, compact and minimal presentations.
    ///
    /// The Dynamic Island is **not** assumed to exist. Every device running this
    /// app shows the Lock Screen presentation; the island is drawn on the
    /// hardware that has one and is a second reading of the same snapshot, never
    /// the only place a fact appears.
    private func dynamicIsland(for state: ShiftActivityAttributes.ContentState) -> DynamicIsland {
        DynamicIsland {
            // Centre and bottom only. The leading and trailing regions are a few
            // points wide beside the camera housing, and a working figure put in
            // one of them loses its first digit at the rounded corner, which on
            // this surface means a driver reads eight minutes as one hour and
            // eight. The two wide regions carry everything instead.
            DynamicIslandExpandedRegion(.center) {
                HStack(alignment: .firstTextBaseline) {
                    Label(state.statusTitle, systemImage: state.statusSymbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.isPaused ? .orange : .red)
                    Spacer(minLength: 8)
                    ShiftActivityWorkingTime(state: state)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    ShiftActivityParkedNotice(state: state)
                    Text(state.mileageLine)
                        .font(.subheadline)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Recorded mileage")
                        .accessibilityValue(state.spokenMileageLine)
                    ShiftActivityDeliveryLine(state: state)
                    ShiftActivityDeliveryTimers(state: state)
                    ShiftActivityControls(state: state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } compactLeading: {
            Image(systemName: state.statusSymbolName)
                .foregroundStyle(state.isPaused ? .orange : .red)
                .accessibilityLabel(state.statusTitle)
        } compactTrailing: {
            // The count of open deliveries rather than a distance. A mileage
            // figure with the word "recorded" trimmed off to fit is exactly the
            // claim this project refuses to make, and a count needs no
            // qualifier to be true.
            Text(state.compactDeliveryCount)
                .monospacedDigit()
                .accessibilityLabel("Deliveries in progress")
                .accessibilityValue(state.compactDeliveryCount)
        } minimal: {
            // One glyph, and nothing to read it by. The whole snapshot is the
            // spoken value here, because this is the presentation where a
            // listener has no other line to fall back on.
            Image(systemName: state.statusSymbolName)
                .foregroundStyle(state.isPaused ? .orange : .red)
                .accessibilityLabel(state.statusTitle)
                .accessibilityValue(state.spokenSummary)
        }
        .keylineTint(state.isPaused ? .orange : .red)
    }
}

/// The Lock Screen card.
struct ShiftActivityLockScreenView: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Deliberately two elements rather than one combined one. Combining
            // them would freeze the running shift's clock into a fixed spoken
            // value, and a driver would be told the working time the snapshot
            // was built with rather than the one on screen.
            HStack(alignment: .firstTextBaseline) {
                Label(state.statusTitle, systemImage: state.statusSymbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.isPaused ? .orange : .red)
                Spacer(minLength: 8)
                ShiftActivityWorkingTime(state: state)
            }

            ShiftActivityParkedNotice(state: state)

            Text(state.mileageLine)
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Recorded mileage")
                .accessibilityValue(state.spokenMileageLine)

            ShiftActivityDeliveryLine(state: state)

            ShiftActivityDeliveryTimers(state: state)

            ShiftActivityControls(state: state)
        }
        .padding()
        .activityBackgroundTint(nil)
    }
}

/// The working figure.
///
/// **Counted by the system, not pushed by the app.** While the shift runs the
/// figure is drawn from an anchor instant, so it stays correct with no further
/// updates for the length of the shift; while it is paused it does not move, so
/// it is drawn once. That is the whole reason this surface needs no per-second
/// update cadence.
struct ShiftActivityWorkingTime: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                // A figure that is not moving is named and read out exactly,
                // which is what the app's own panel does while paused.
                Text(state.formattedWorkingTime)
                    .accessibilityLabel("Working time, paused")
                    .accessibilityValue(state.spokenWorkingTime)
            } else {
                // Left unlabelled on purpose. The system draws and speaks this
                // one from its anchor, so any label of ours would replace a live
                // figure with the one this snapshot happened to carry.
                Text(timerInterval: state.workingTimerRange, countsDown: false)
            }
        }
        .font(.title3.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(state.isPaused ? .secondary : .primary)
    }
}

/// How the deliveries stand, and what the one in progress is doing.
struct ShiftActivityDeliveryLine: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.deliveryLine)
                .font(.caption)
            // Only ever present when exactly one delivery is in progress, so
            // this line can never describe the wrong order.
            if let status = state.deliveryStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deliveries")
        .accessibilityValue(
            [state.spokenDeliveryLine, state.deliveryStatus]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
    }
}

/// How long each delivery in progress has been open.
///
/// ## One line per delivery, and the system counts each of them
///
/// `Delivery 1 · 18:04`, one row per open order, drawn from that delivery's own
/// acceptance instant. **Counted by the system, not pushed by the app**, for
/// exactly the reason the shift's own clock is: an anchor stays correct for as
/// long as the delivery is open, and a duration written into the snapshot would
/// be wrong a second later.
///
/// Nothing is added together. Two stacked orders are two lifecycles running
/// over the same minutes, and one combined figure would be longer than the
/// shift and would belong to neither of them.
///
/// A delivered or cancelled delivery simply has no row: the app derives the
/// list from the deliveries that are open, so finishing one stops its clock by
/// removing it rather than by freezing it at a number that looks live.
///
/// ## Two elements per row, deliberately
///
/// The label and the figure are separate, like the shift's clock and its
/// heading. Combining them would freeze the count into whatever this snapshot
/// was built at, and a listener would be told a duration that stopped moving.
/// The label goes on the name, ahead of the figure, so VoiceOver says what the
/// number that follows measures.
/// The one line that says the route has stopped because the driver parked.
///
/// Drawn directly above the mileage figure, which is the figure it explains: a
/// distance that has stopped growing with no reason beside it reads as a
/// recording fault. It is **not** the paused styling and must not become it —
/// the status line above still says the shift is running, because it is.
///
/// Absent entirely when the driver has not parked, so a card the feature never
/// touches is the card it always was.
struct ShiftActivityParkedNotice: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        if let notice = state.routeSuspendedNotice {
            Label(notice, systemImage: "parkingsign.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .accessibilityLabel(state.spokenRouteSuspendedNotice ?? notice)
        }
    }
}

struct ShiftActivityDeliveryTimers: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        if !state.activeDeliveryTimers.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(state.drawnDeliveryTimers, id: \.self) { timer in
                    row(for: timer)
                }

                if let notice = state.undrawnDeliveryTimerNotice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(state.spokenUndrawnDeliveryTimerNotice ?? notice)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(for timer: ShiftActivityDeliveryTimer) -> some View {
        HStack(spacing: 4) {
            // The subject, and the one element carrying a spoken label. The
            // middle dot is hidden from VoiceOver for the reason it is
            // everywhere else in this app: it is punctuation, not a word.
            Text(timer.title)
                .accessibilityLabel(timer.spokenLabel)
            Text(verbatim: "·")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // What this delivery is doing. With two orders open the card names
            // both and `deliveryStatus` is withheld, so without this the Lock
            // Screen says what neither of them is waiting for.
            //
            // Hidden from VoiceOver because the element above already speaks it:
            // its label is the whole sentence, so a second element saying the
            // state again would be the card repeating itself. It gives way
            // first when the row is too narrow, which is why it carries no
            // layout priority and the figure does.
            if let state = timer.stateLabel {
                Text(state)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            // Left unlabelled on purpose. The system draws and speaks this one
            // from the anchor, so any label of ours would replace a live figure
            // with the one this snapshot happened to carry.
            Text(timerInterval: timer.timerRange, countsDown: false)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .font(.caption)
        .lineLimit(1)
    }
}

/// The controls the app said this shift may offer, and the sentence for the step
/// it withheld.
///
/// The two are no longer alternatives. A shift with several orders open is
/// offered Start Delivery, which names no particular one of them, **and** told
/// why the step control is missing, because the missing control is the thing
/// that needs explaining.
///
/// A running shift with nothing open now offers three controls, which is one
/// more than a Lock Screen card fits on a line at the larger accessibility text
/// sizes. ``ViewThatFits`` takes the single row where it fits and wraps to two
/// rows where it does not, rather than truncating a label: a button whose words
/// are cut short is a button a driver has to guess at, which on this surface is
/// how the wrong thing gets recorded.
struct ShiftActivityControls: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.controls.isEmpty {
                ViewThatFits(in: .horizontal) {
                    row(of: state.controls)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(wrapped.enumerated()), id: \.offset) { _, line in
                            row(of: line)
                        }
                    }
                }
            }

            if let notice = state.controlNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The controls in rows of at most two, in the order the app put them in.
    private var wrapped: [[ShiftActivityControl]] {
        stride(from: 0, to: state.controls.count, by: 2).map { start in
            Array(state.controls[start..<min(start + 2, state.controls.count)])
        }
    }

    private func row(of controls: [ShiftActivityControl]) -> some View {
        HStack(spacing: 8) {
            ForEach(controls, id: \.self) { control in
                ShiftActivityControlButton(
                    control: control,
                    isEmphasised: control == ShiftActivityControl.emphasised(in: state.controls)
                )
            }
        }
    }
}

/// One control.
///
/// The intent is chosen by a switch rather than by a lookup returning an
/// existential, because a button has to name a concrete intent type. Each of
/// them is performed in the **app's** process and refused there by the app's own
/// rules, so a button shown against a snapshot that is a moment out of date
/// costs a refusal sentence rather than a wrong write.
struct ShiftActivityControlButton: View {
    let control: ShiftActivityControl

    /// Whether this is the one control on the card that carries the emphasis.
    ///
    /// Decided for the list rather than for the control, by
    /// ``ShiftActivityControl/emphasised(in:)``: a card offering a delivery's
    /// next step *and* Start Delivery has two controls that would each take the
    /// emphasis on their own, and emphasising both emphasises neither.
    let isEmphasised: Bool

    var body: some View {
        Group {
            switch control {
            case .pause:
                Button(intent: PauseShiftFromActivityIntent()) { label }
            case .resume:
                Button(intent: ResumeShiftFromActivityIntent()) { label }
            case .end:
                Button(intent: EndShiftFromActivityIntent()) { label }
            case .startDelivery:
                Button(intent: StartDeliveryFromActivityIntent()) { label }
            case .park:
                Button(intent: ParkVehicleFromActivityIntent()) { label }
            case .resumeDriving:
                Button(intent: ResumeDrivingFromActivityIntent()) { label }
            case .deliveryStep:
                Button(intent: RecordDeliveryProgressFromActivityIntent()) { label }
            }
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .accessibilityLabel(control.spokenLabel)
    }

    private var label: some View {
        Label(control.title, systemImage: control.symbolName)
            .font(.caption.weight(isEmphasised ? .semibold : .regular))
            .lineLimit(1)
    }

    /// Red only on End, which is the one action here a driver cannot undo from
    /// this surface.
    private var tint: Color {
        switch control {
        case .end: .red
        case .pause, .resume, .startDelivery, .park, .resumeDriving, .deliveryStep: .accentColor
        }
    }
}
