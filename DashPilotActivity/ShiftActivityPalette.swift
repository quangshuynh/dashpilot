import SwiftUI
import UIKit

/// The Live Activity's colours: the app's status tints and its route accent,
/// so the Lock Screen and the Dynamic Island say each state in the same hue the
/// app does.
///
/// Compiled into the app and into the widget extension, like everything in this
/// folder. The extension has no asset catalog, so the accent is spelled out
/// here with the same light and dark values as the app's `AccentColor`, and
/// `DashStatusTint` in the app reads its status hues from here, so the two can
/// never drift apart. Each hue is the third signal after a symbol and a word.
nonisolated enum ShiftActivityPalette {
    /// The route accent: a control's tint, never decoration.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1E / 255, green: 0x9C / 255, blue: 0x8B / 255, alpha: 1)
            : UIColor(red: 0x0F / 255, green: 0x76 / 255, blue: 0x6E / 255, alpha: 1)
    })

    /// Recording: the convention for it.
    static let running = Color.red
    /// Working time stopped.
    static let paused = Color.orange
    /// The vehicle parked, route not recording: the parking-sign convention.
    static let parked = Color.blue

    /// The hue for a state the island and the card's header draw.
    static func tint(for status: ShiftActivityCompactStatus) -> Color {
        switch status {
        case .running: running
        case .paused: paused
        case .parked: parked
        }
    }
}
