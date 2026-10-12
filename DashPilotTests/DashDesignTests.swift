import SwiftUI
import Testing
import UIKit
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


/// Measured color contracts, including the separately compiled widget palette.
/// These catch a bright dark-mode link color accidentally becoming a white-text
/// fill, and drift between the asset catalog and the extension.
@MainActor
@Suite("Design contrast")
struct DashContrastTests {
    @Test("Text pairs retain ordinary-text contrast in both appearances and contrast settings")
    func textContrast() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for contrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection { traits in
                    traits.userInterfaceStyle = style
                    traits.accessibilityContrast = contrast
                }
                let pairs: [(Color, Color)] = [
                    (ShiftActivityPalette.onAction, ShiftActivityPalette.actionFill),
                    (ShiftActivityPalette.onAction, ShiftActivityPalette.mutedFill),
                    (ShiftActivityPalette.accent, ShiftActivityPalette.cloud),
                    (ShiftActivityPalette.accent, ShiftActivityPalette.canvas),
                    (Color(uiColor: .label), ShiftActivityPalette.cloud)
                ]
                for (foreground, background) in pairs {
                    let a = try luminance(UIColor(foreground).resolvedColor(with: traits))
                    let b = try luminance(UIColor(background).resolvedColor(with: traits))
                    let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
                    #expect(ratio >= 4.5, "Text contrast \(ratio), appearance \(style.rawValue), contrast \(contrast.rawValue)")
                }
                let asset = try #require(UIColor(named: "AccentColor", in: .main, compatibleWith: traits))
                let shared = UIColor(ShiftActivityPalette.accent).resolvedColor(with: traits)
                #expect(abs(try luminance(asset.resolvedColor(with: traits)) - luminance(shared)) < 0.0001)
            }
        }
    }

    private func luminance(_ color: UIColor) throws -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        let channels = [r, g, b].map { value -> Double in
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}
