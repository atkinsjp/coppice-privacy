//
//  WidgetDesign.swift
//  StillhabitWidget
//
//  Widget-target copy of Stillhabit's design tokens.
//  Warm, muted, and quiet — never pure white, never pure black.
//

import SwiftUI
import UIKit

enum WidgetDesign {
    /// Warm ivory in light mode, deep matte charcoal in dark mode.
    static let background = Color(lightHex: "F9F8F6", darkHex: "1C1E1D")

    /// Warm near-black / warm off-white text.
    static let textPrimary = Color(lightHex: "3A3C38", darkHex: "E8E6E1")

    /// Muted stone gray for supporting text.
    static let textSecondary = Color(lightHex: "9B998F", darkHex: "8D908B")

    /// Ivory used on top of accent fills. Slightly warmer in dark mode.
    static let onAccent = Color(lightHex: "F9F8F6", darkHex: "F4F2EC")

    /// Default earth-tone accent — lifted in dark mode for readability.
    static let sage = Color(lightHex: "8A9A86", darkHex: "A0B09C")

    /// Mapping of stored habit color hexes to their dark-mode counterparts,
    /// mirroring the app's `DesignSystem` palette so widgets stay consistent.
    private static let darkColorMap: [String: String] = [
        "8A9A86": "A0B09C",
        "C8826D": "D89580",
        "7A8B99": "94A8B8",
        "D8B08C": "E4BE9C",
        "B9908C": "CDA4A0",
        "6F7D65": "889A7E",
        "B08D6E": "C5A084",
        "9A92A8": "B0A8BC",
        "5E7268": "7A9084",
        "A8A196": "BCB8AE",
    ]

    /// Resolves a stored habit color hex into a dynamic Color that adapts to
    /// the current color scheme. Unknown hexes fall back to the raw value.
    static func habitColor(forHex hex: String) -> Color {
        let dark = darkColorMap[hex.uppercased()] ?? hex
        return Color(lightHex: hex, darkHex: dark)
    }
}

extension Color {
    /// Creates a color from a hex string like "8A9A86" or "#8A9A86".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    /// Creates a dynamic color that resolves to different hex values in light and dark mode.
    init(lightHex: String, darkHex: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: darkHex))
                : UIColor(Color(hex: lightHex))
        })
    }
}
