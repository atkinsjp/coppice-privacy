//
//  StillHabitLogoView.swift
//  CoppiceHabitsThatRest
//
//  A serene, vector-based emblem representing quiet consistency:
//  a smooth Zen stone resting at the center of gentle concentric
//  ripple rings — the visual metaphor for a calm habit settling
//  into stillness. Renders crisply at any size; tuned for 44pt.
//

import SwiftUI

struct StillHabitLogoView: View {
    /// Edge length of the rounded-square badge. Defaults to 44pt — the
    /// standard iOS home-screen icon target.
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            // Smooth, subtle gradient badge — warm ivory to soft sage mist.
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(lightHex: "F4F2EC", darkHex: "2A2D2B"),
                            Color(lightHex: "E6E8E2", darkHex: "232624")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Faint sage halo behind the stone, suggesting still water.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DesignSystem.Colors.sage.opacity(0.16),
                            DesignSystem.Colors.sage.opacity(0)
                        ],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.42
                    )
                )

            emblem
                .frame(width: size * 0.82, height: size * 0.82)
        }
        .frame(width: size, height: size)
        .scaledToFit()
        .shadow(
            color: Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.black.withAlphaComponent(0.22)
                    : UIColor.black.withAlphaComponent(0.05)
            }),
            radius: 8, x: 0, y: 2
        )
        .accessibilityHidden(true)
    }

    /// The concentric ripple rings + centered Zen stone.
    private var emblem: some View {
        ZStack {
            // Three concentric ripple rings, fading outward.
            rippleRing(lineWidth: size * 0.024, scale: 1.00, opacity: 0.22)
            rippleRing(lineWidth: size * 0.022, scale: 0.72, opacity: 0.34)
            rippleRing(lineWidth: size * 0.020, scale: 0.48, opacity: 0.50)

            // The resting stone — a soft, flattened ellipse with a gentle
            // gradient that catches light from the upper-left.
            ZenStone(size: size)
        }
    }

    /// A single concentric ripple ring, stroked in sage.
    private func rippleRing(
        lineWidth: CGFloat,
        scale: CGFloat,
        opacity: Double
    ) -> some View {
        Circle()
            .stroke(DesignSystem.Colors.sage.opacity(opacity), lineWidth: lineWidth)
            .scaleEffect(scale)
    }
}

// MARK: - Zen stone

/// A smooth, slightly flattened river-stone ellipse with a subtle ochre-tinted
/// highlight, suggesting warmth and weight.
private struct ZenStone: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Stone body — a gentle radial gradient from sage-tinted stone
            // to a deeper, grounded shade.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            DesignSystem.Colors.sage.opacity(0.92),
                            Color(lightHex: "6F7E6B", darkHex: "5A6A56")
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: size * 0.02,
                        endRadius: size * 0.30
                    )
                )
                .frame(width: size * 0.44, height: size * 0.30)

            // Soft ochre highlight — a quiet glint of warmth on the stone.
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            DesignSystem.Colors.softOchre.opacity(0.55),
                            DesignSystem.Colors.softOchre.opacity(0)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.12
                    )
                )
                .frame(width: size * 0.22, height: size * 0.12)
                .offset(x: -size * 0.05, y: -size * 0.04)
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        StillHabitLogoView(size: 44)
        StillHabitLogoView(size: 64)
        StillHabitLogoView(size: 88)
    }
    .padding(32)
    .background(DesignSystem.Colors.background)
}
