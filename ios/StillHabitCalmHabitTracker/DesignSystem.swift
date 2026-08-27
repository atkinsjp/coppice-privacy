//
//  DesignSystem.swift
//  StillHabitCalmHabitTracker
//
//  The single source of truth for StillHabitCalmHabitTracker's visual language.
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

        /// Deep matte charcoal for small text that must stay legible over the
        /// earthy wave background (weekday initials, dense micro-labels).
        /// Inverts to a bright warm ivory in dark mode so contrast holds both ways.
        static let textStrong = Color(lightHex: "1C1E1D", darkHex: "F2F0EA")

        /// Ivory used on top of accent fills (buttons, checkmarks).
        /// Slightly warmer in dark mode so it sits calmly on saturated fills.
        static let onAccent = Color(lightHex: "F9F8F6", darkHex: "F4F2EC")

        // Earth-toned accent palette — each lifted in dark mode to stay
        // calming yet readable against the deep charcoal background.
        static let sage = Color(lightHex: "8A9A86", darkHex: "A0B09C")
        static let terracotta = Color(lightHex: "C8826D", darkHex: "D89580")
        static let slateBlue = Color(lightHex: "7A8B99", darkHex: "94A8B8")
        static let softOchre = Color(lightHex: "D8B08C", darkHex: "E4BE9C")
    }

    // MARK: - Palette

    struct HabitColor: Identifiable {
        let name: String
        let hex: String
        let darkHex: String
        var id: String { hex }
        /// A dynamic color that resolves to the light hex in light mode and the
        /// lifted dark hex in dark mode.
        var color: Color { Color(lightHex: hex, darkHex: darkHex) }
    }

    /// Resolves a stored habit color hex into a dynamic Color that adapts to
    /// the current color scheme. The static palette and premium palette values
    /// are mapped to their dark-mode counterparts; any unknown hex (e.g. a
    /// custom value from an older schema) falls back to the raw hex in both
    /// modes so legacy habits never break.
    static func habitColor(forHex hex: String) -> Color {
        let all = palette + premiumPalette
        if let match = all.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) {
            return match.color
        }
        return Color(hex: hex)
    }

    /// The only accent colors habits may use. Each entry carries a dark-mode
    /// hex that lifts the tone just enough to stay readable on charcoal without
    /// losing its earthy character.
    static let palette: [HabitColor] = [
        HabitColor(name: "Sage", hex: "8A9A86", darkHex: "A0B09C"),
        HabitColor(name: "Terracotta", hex: "C8826D", darkHex: "D89580"),
        HabitColor(name: "Slate", hex: "7A8B99", darkHex: "94A8B8"),
        HabitColor(name: "Ochre", hex: "D8B08C", darkHex: "E4BE9C"),
    ]

    /// Additional muted tones unlocked with StillHabitCalmHabitTracker Pro.
    static let premiumPalette: [HabitColor] = [
        HabitColor(name: "Dusty Rose", hex: "B9908C", darkHex: "CDA4A0"),
        HabitColor(name: "Moss", hex: "6F7D65", darkHex: "889A7E"),
        HabitColor(name: "Clay", hex: "B08D6E", darkHex: "C5A084"),
        HabitColor(name: "Lavender Ash", hex: "9A92A8", darkHex: "B0A8BC"),
        HabitColor(name: "Pine", hex: "5E7268", darkHex: "7A9084"),
        HabitColor(name: "Stone", hex: "A8A196", darkHex: "BCB8AE"),
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
    /// In dark mode the shadow is deeper so cards still separate gently from
    /// the charcoal background without a harsh outline.
    func softShadow() -> some View {
        shadow(
            color: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.28)
                    : UIColor.black.withAlphaComponent(0.04)
            }),
            radius: 12,
            x: 0,
            y: 4
        )
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
