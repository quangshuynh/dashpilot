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
                .activityBackgroundTint(nil)
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
                ShiftActivityHeader(state: state)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            // The orders as far as the region has room, and the controls, in the
            // app's order. No mileage line: it is on the Lock Screen card, and
            // the island is a second reading of the same snapshot.
            DynamicIslandExpandedRegion(.bottom) {
                ShiftActivityIslandBottom(state: state)
            }
        } compactLeading: {
            // The header's symbol and words, so parked shows the parking sign
            // rather than the recording dot.
            Image(systemName: state.headerSymbolName)
                .foregroundStyle(tint(for: state))
                .accessibilityLabel(state.spokenHeaderTitle)
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
            Image(systemName: state.headerSymbolName)
                .foregroundStyle(tint(for: state))
                .accessibilityLabel(state.spokenHeaderTitle)
                .accessibilityValue(state.spokenSummary)
        }
        .keylineTint(tint(for: state))
    }

    /// Red while recording, orange while paused, blue while parked: never the
    /// recording red for a route that is not being recorded.
    private func tint(for state: ShiftActivityAttributes.ContentState) -> Color {
        switch state.compactStatus {
        case .running: .red
        case .paused: .orange
        case .parked: .blue
        }
    }
}
