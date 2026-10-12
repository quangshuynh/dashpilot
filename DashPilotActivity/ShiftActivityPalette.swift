import SwiftUI
import UIKit

/// Shared appearance roles for the app and its Live Activity. The extension
/// has no asset catalog. AccentColor mirrors the foreground accent here;
/// filled controls deliberately use their own background and foreground pair.
nonisolated enum ShiftActivityPalette {
    static let accent = adaptive(light: 0x315FCC, dark: 0x8EADFF, highLight: 0x244B9F, highDark: 0xB7CAFF)
    static let actionFill = adaptive(light: 0x315FCC, dark: 0x315FCC, highLight: 0x244B9F, highDark: 0x244B9F)
    static let onAction = Color.white
    static let canvas = adaptive(light: 0xF5F7FB, dark: 0x161A22)
    static let cloud = adaptive(light: 0xEBF0F8, dark: 0x222D40)
    static let outline = adaptive(light: 0xCBD5E5, dark: 0x475773, highLight: 0x65758E, highDark: 0x99ABC9)
    static let estimateOutline = adaptive(light: 0x65758E, dark: 0x99ABC9)
    static let mutedFill = adaptive(light: 0x566174, dark: 0x566174)

    // State is always also named and given a symbol. Brand blue never replaces
    // the recording red, paused orange, or parking-sign blue.
    static let running = Color.red
    static let paused = Color.orange
    static let parked = Color.blue

    static func tint(for status: ShiftActivityCompactStatus) -> Color {
        switch status {
        case .running: running
        case .paused: paused
        case .parked: parked
        }
    }

    private static func adaptive(
        light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let highContrast = traits.accessibilityContrast == .high
            let value = isDark
                ? (highContrast ? highDark ?? dark : dark)
                : (highContrast ? highLight ?? light : light)
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
