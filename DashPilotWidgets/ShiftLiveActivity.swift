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
                    Text(state.mileageLine)
                        .font(.subheadline)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Recorded mileage")
                        .accessibilityValue(state.spokenMileageLine)
                    ShiftActivityDeliveryLine(state: state)
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

            Text(state.mileageLine)
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Recorded mileage")
                .accessibilityValue(state.spokenMileageLine)

            ShiftActivityDeliveryLine(state: state)

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

/// The controls the app said this shift may offer, and the sentence for when it
/// said none.
struct ShiftActivityControls: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        if let notice = state.controlNotice {
            Text(notice)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                ForEach(state.controls, id: \.self) { control in
                    ShiftActivityControlButton(control: control)
                }
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

    var body: some View {
        Group {
            switch control {
            case .pause:
                Button(intent: PauseShiftFromActivityIntent()) { label }
            case .resume:
                Button(intent: ResumeShiftFromActivityIntent()) { label }
            case .end:
                Button(intent: EndShiftFromActivityIntent()) { label }
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
            .font(.caption.weight(control.isProminent ? .semibold : .regular))
            .lineLimit(1)
    }

    /// Red only on End, which is the one action here a driver cannot undo from
    /// this surface.
    private var tint: Color {
        switch control {
        case .end: .red
        case .pause, .resume, .deliveryStep: .accentColor
        }
    }
}
