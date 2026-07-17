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

    /// Ivory used on top of accent fills.
    static let onAccent = Color(hex: "F9F8F6")

    /// Default earth-tone accent.
    static let sage = Color(hex: "8A9A86")
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
