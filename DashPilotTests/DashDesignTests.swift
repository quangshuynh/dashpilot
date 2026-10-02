import SwiftUI
import Testing
@testable import DashPilot

/// The stop track draws a delivery's state; it must agree with the lifecycle
/// order rather than with a list of states someone typed in a view.
@Suite("Dash design")
struct DashDesignTests {
    @Test("Each state on the lifecycle sits one stop further along, in lifecycle order")
    func stopTrackFollowsTheLifecycle() {
        let onTrack: [DeliveryState] = [.accepted, .arrivedAtPickup, .pickedUp, .delivered]
        #expect(onTrack.compactMap(\.stopTrackIndex) == Array(0..<DeliveryState.stopTrackCount))
        #expect(onTrack.count == DeliveryState.stopTrackCount)
    }

    @Test("A cancelled delivery is not on the track, so it draws nothing rather than a stop")
    func cancelledIsOffTheTrack() {
        #expect(DeliveryState.cancelled.stopTrackIndex == nil)
    }

    /// The next step a card offers is always the stop after the one it is at,
    /// so the ring on the track and the button under it describe one moment.
    @Test("The stop a delivery is at is followed by the step its card offers")
    func nextStepIsTheFollowingStop() {
        for state in [DeliveryState.accepted, .arrivedAtPickup, .pickedUp] {
            let index = state.stopTrackIndex ?? -1
            let next = DeliveryState.allCases.first { $0.stopTrackIndex == index + 1 }
            #expect(next != nil, "\(state) has no stop after it")
            #expect(state.nextAction != nil, "\(state) offers no next step")
        }
        #expect(DeliveryState.delivered.nextAction == nil)
    }

    /// The Lock Screen header used the paused orange for a parked shift while
    /// the island used blue. One palette now draws both, and the app's own
    /// status tints are read from it.
    @Test("Parked, paused and running each have their own hue, shared by the app and the Live Activity")
    func statusHuesAreSharedAndDistinct() {
        let hues = [ShiftActivityCompactStatus.running, .paused, .parked].map(ShiftActivityPalette.tint(for:))
        #expect(Set(hues.map { "\($0)" }).count == 3)
        #expect(DashStatusTint.running == ShiftActivityPalette.tint(for: .running))
        #expect(DashStatusTint.paused == ShiftActivityPalette.tint(for: .paused))
        #expect(DashStatusTint.parked == ShiftActivityPalette.tint(for: .parked))
    }
}
