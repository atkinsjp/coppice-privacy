//
//  DesignSystem.swift
//  Stillhabit
//
//  The single source of truth for Stillhabit's visual language.
//  Warm, muted, and quiet — never pure white, never pure black.
//

import SwiftUI

enum DesignSystem {

    // MARK: - Colors

    enum Colors {
        /// Warm ivory in light mode, deep matte charcoal in dark mode.
        static let background = Color(lightHex: "F9F8F6", darkHex: "1C1E1D")

        /// Slightly elevated surface for cards and fields.
        static let card = Color(lightHex: "FDFCFA", darkHex: "252827")

        /// Warm near-black / warm off-white text.
        static let textPrimary = Color(lightHex: "3A3C38", darkHex: "E8E6E1")

        /// Muted stone gray for supporting text.
        static let textSecondary = Color(lightHex: "9B998F", darkHex: "8D908B")

        /// Ivory used on top of accent fills (buttons, checkmarks).
        static let onAccent = Color(hex: "F9F8F6")

        // Earth-toned accent palette.
        static let sage = Color(hex: "8A9A86")
        static let terracotta = Color(hex: "C8826D")
        static let slateBlue = Color(hex: "7A8B99")
        static let softOchre = Color(hex: "D8B08C")
    }

    // MARK: - Palette

    struct HabitColor: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) }
    }

    /// The only accent colors habits may use.
    static let palette: [HabitColor] = [
        HabitColor(name: "Sage", hex: "8A9A86"),
        HabitColor(name: "Terracotta", hex: "C8826D"),
        HabitColor(name: "Slate", hex: "7A8B99"),
        HabitColor(name: "Ochre", hex: "D8B08C"),
    ]

    /// Additional muted tones unlocked with Stillhabit Pro.
    static let premiumPalette: [HabitColor] = [
        HabitColor(name: "Dusty Rose", hex: "B9908C"),
        HabitColor(name: "Moss", hex: "6F7D65"),
        HabitColor(name: "Clay", hex: "B08D6E"),
        HabitColor(name: "Lavender Ash", hex: "9A92A8"),
        HabitColor(name: "Pine", hex: "5E7268"),
        HabitColor(name: "Stone", hex: "A8A196"),
    ]

    // MARK: - Typography

    enum Typography {
        /// SF Pro Rounded for the main screen title.
        static let largeHeader = Font.system(size: 34, weight: .semibold, design: .rounded)
        /// SF Pro Rounded for sheet and section headers.
        static let sectionHeader = Font.system(size: 22, weight: .semibold, design: .rounded)
        /// SF Pro Rounded for numbers and counters.
        static let number = Font.system(size: 15, weight: .medium, design: .rounded)
        /// Clean SF Pro Text for habit titles and labels.
        static let label = Font.system(size: 17, weight: .regular)
        /// SF Pro Rounded for small supporting numerals (streaks).
        static let smallNumber = Font.system(size: 13, weight: .medium, design: .rounded)
        /// Small uppercase date line.
        static let overline = Font.system(size: 12, weight: .medium)
        /// Quiet supporting copy.
        static let caption = Font.system(size: 14, weight: .regular)
    }

    // MARK: - Layout

    enum Layout {
        /// Generous minimum horizontal padding.
        static let horizontalPadding: CGFloat = 24
        static let cardCornerRadius: CGFloat = 20
        static let fieldCornerRadius: CGFloat = 14
        static let rowSpacing: CGFloat = 14
    }
}

// MARK: - Soft shadow

extension View {
    /// The one and only shadow in the app: soft, diffused, barely there.
    func softShadow() -> some View {
        shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Card press style

/// Gentle scale-down feedback for tappable cards.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
