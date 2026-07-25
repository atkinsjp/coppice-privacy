//
//  WavyBackgroundView.swift
//  Stillhabit
//
//  A continuously animated, earthy mesh-gradient background.
//  Moss, taupe, and a whisper of terracotta ebb and flow like
//  slow water — quiet enough to never compete with content.
//

import SwiftUI

/// The signature animated backdrop for the Today view.
///
/// A 4×4 `MeshGradient` whose interior control points drift on layered
/// sine/cosine waves driven by a `TimelineView`. Rendering is fully
/// GPU-accelerated, and the palette is kept close to the warm ivory /
/// charcoal base so foreground text remains perfectly legible.
struct WavyBackgroundView: View {
    /// When true, a warm golden/ochre glow gently pulses and expands outward
    /// over ~3 seconds — the visual half of the "Still Moment" reward that
    /// fires when every scheduled habit for the day is complete. The glow
    /// lives at the background layer (behind all content) so it never
    /// interferes with touch targets.
    var warmGlow: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        meshBackground
            .ignoresSafeArea()
            .overlay {
                if warmGlow {
                    WarmGlowPulse(reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }

    @ViewBuilder
    private var meshBackground: some View {
        if reduceMotion {
            meshGradient(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                meshGradient(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    // MARK: - Mesh

    private func meshGradient(at time: TimeInterval) -> some View {
        MeshGradient(
            width: 4,
            height: 4,
            points: animatedPoints(at: time),
            colors: colorScheme == .dark ? Self.darkColors : Self.lightColors,
            smoothsColors: true
        )
    }

    /// Produces the 16 control points of the mesh, gently displacing the
    /// interior points on slow, layered sine waves so colors appear to
    /// drift and breathe across the screen.
    private func animatedPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time)

        /// Smooth two-axis wobble for an interior point.
        func drift(_ x: Float, _ y: Float, speed: Float, phase: Float, amp: Float) -> SIMD2<Float> {
            SIMD2<Float>(
                x + sin(t * speed + phase) * amp,
                y + cos(t * speed * 0.8 + phase * 1.7) * amp
            )
        }

        /// Slide a point along an edge (one axis stays pinned).
        func edgeSlide(_ value: Float, speed: Float, phase: Float, amp: Float) -> Float {
            value + sin(t * speed + phase) * amp
        }

        return [
            // Top edge — pinned to y = 0, x drifts slightly.
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(edgeSlide(0.33, speed: 0.11, phase: 0.4, amp: 0.06), 0.0),
            SIMD2<Float>(edgeSlide(0.66, speed: 0.09, phase: 2.1, amp: 0.06), 0.0),
            SIMD2<Float>(1.0, 0.0),

            // Upper interior row.
            SIMD2<Float>(0.0, edgeSlide(0.33, speed: 0.10, phase: 1.2, amp: 0.05)),
            drift(0.36, 0.30, speed: 0.14, phase: 0.0, amp: 0.10),
            drift(0.64, 0.36, speed: 0.12, phase: 2.4, amp: 0.10),
            SIMD2<Float>(1.0, edgeSlide(0.30, speed: 0.08, phase: 3.3, amp: 0.05)),

            // Lower interior row.
            SIMD2<Float>(0.0, edgeSlide(0.68, speed: 0.09, phase: 4.0, amp: 0.05)),
            drift(0.33, 0.66, speed: 0.11, phase: 4.8, amp: 0.11),
            drift(0.68, 0.64, speed: 0.13, phase: 1.6, amp: 0.11),
            SIMD2<Float>(1.0, edgeSlide(0.66, speed: 0.10, phase: 0.9, amp: 0.05)),

            // Bottom edge — pinned to y = 1.
            SIMD2<Float>(0.0, 1.0),
            SIMD2<Float>(edgeSlide(0.34, speed: 0.10, phase: 5.2, amp: 0.06), 1.0),
            SIMD2<Float>(edgeSlide(0.67, speed: 0.12, phase: 2.8, amp: 0.06), 1.0),
            SIMD2<Float>(1.0, 1.0),
        ]
    }

    // MARK: - Palettes

    /// Light mode: warm ivory washed with soft moss, muted taupe,
    /// and a faint breath of terracotta. Everything stays near-ivory
    /// so foreground content keeps full contrast.
    private static let lightColors: [Color] = [
        Color(hex: "F7F6F2"), Color(hex: "F1F2EB"), Color(hex: "F6F3EE"), Color(hex: "F4F1EA"),
        Color(hex: "EFF1E9"), Color(hex: "E4E9DD"), Color(hex: "EFE6DE"), Color(hex: "F0EDE4"),
        Color(hex: "F3EEE6"), Color(hex: "EAE4D9"), Color(hex: "E7EBDF"), Color(hex: "EDEFE6"),
        Color(hex: "F6F4EF"), Color(hex: "EFEBE1"), Color(hex: "EBEEE4"), Color(hex: "F5F2EC"),
    ]

    /// Dark mode: deep matte charcoal breathing with mossy green,
    /// warm umber, and cool stone — equally quiet.
    private static let darkColors: [Color] = [
        Color(hex: "1C1E1D"), Color(hex: "1E211E"), Color(hex: "201F1D"), Color(hex: "1D1F1E"),
        Color(hex: "1F221F"), Color(hex: "232823"), Color(hex: "262220"), Color(hex: "202220"),
        Color(hex: "22211E"), Color(hex: "272420"), Color(hex: "232722"), Color(hex: "1F221F"),
        Color(hex: "1D1F1E"), Color(hex: "21231F"), Color(hex: "202320"), Color(hex: "1C1E1D"),
    ]
}

#Preview("Light") {
    WavyBackgroundView()
}

#Preview("Dark") {
    WavyBackgroundView()
        .preferredColorScheme(.dark)
}

// MARK: - Warm glow pulse

/// The visual "Still Moment" — a soft radial wash of warm golden/ochre light
/// that blooms outward from the center over ~3 seconds, then fades back to
/// let the earthy mesh return to its resting state. Rendered inside the
/// background layer so it stays behind all foreground content and never
/// captures touches.
private struct WarmGlowPulse: View {
    let reduceMotion: Bool

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0

    var body: some View {
        RadialGradient(
            colors: [
                Color(hex: "E8B574").opacity(0.9),
                Color(hex: "D8B08C").opacity(0.45),
                .clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 340
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear { animate() }
    }

    private func animate() {
        guard !reduceMotion else {
            // Respect Reduce Motion: a single calm bloom, no expansive sweep.
            withAnimation(.easeInOut(duration: 1.2)) {
                opacity = 0.5
                scale = 1.4
            }
            return
        }
        // Expand outward over the full ~3s while opacity pulses up then fades.
        withAnimation(.easeOut(duration: 3.2)) {
            scale = 2.8
        }
        withAnimation(.easeIn(duration: 0.9)) {
            opacity = 0.72
        }
        Task {
            try? await Task.sleep(for: .seconds(0.95))
            withAnimation(.easeOut(duration: 2.25)) {
                opacity = 0
            }
        }
    }
}
