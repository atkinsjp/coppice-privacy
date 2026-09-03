//
//  ProCelebrationView.swift
//  CoppiceHabitsThatRest
//
//  The quiet thank-you that plays over the Today screen right after a
//  subscription purchase succeeds.
//
//  Not confetti in the party-popper sense — that would be off-key for this
//  app. Instead: two soft sage ripples breathe outward from the centre, a
//  handful of small leaf-toned petals drift down the screen like the first
//  seconds of light rain, and one italic line settles in the middle. The
//  whole thing is built from plain SwiftUI offset/opacity/rotation animations
//  driven by a single state flip — every animation runs on the render server,
//  nothing redraws per frame, so it stays safe in the IOSurface-denied
//  sandbox and costs nothing on the main thread.
//

import SwiftUI

struct ProCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One drifting petal. All randomness is decided once, up front, so the
    /// body stays a pure function of `hasBegun`.
    private struct Petal: Identifiable {
        let id: Int
        /// Horizontal start position as a fraction of the screen width.
        let xFraction: CGFloat
        /// Sideways drift accumulated over the whole fall, in points.
        let drift: CGFloat
        let width: CGFloat
        let height: CGFloat
        /// Fraction of the screen height where the fall ends.
        let fallDistance: CGFloat
        let delay: Double
        let duration: Double
        /// Total rotation over the fall, degrees. Signed, so petals tumble
        /// both ways.
        let spin: Double
        let color: Color
        let opacity: Double
    }

    /// One expanding ripple ring.
    private struct Ripple: Identifiable {
        let id: Int
        let delay: Double
        let duration: Double
        let endScale: CGFloat
    }

    private let petals: [Petal]
    private let ripples: [Ripple]

    /// The single flip that launches every animation in the view.
    @State private var hasBegun = false

    init() {
        let palette: [Color] = [
            DesignSystem.Colors.sage,
            DesignSystem.Colors.softOchre,
            DesignSystem.Colors.slateBlue,
        ]
        petals = (0..<14).map { index in
            Petal(
                id: index,
                xFraction: CGFloat.random(in: 0.06...0.94),
                drift: CGFloat.random(in: -34...34),
                width: CGFloat.random(in: 5...8),
                height: CGFloat.random(in: 10...16),
                fallDistance: CGFloat.random(in: 0.55...0.85),
                delay: Double.random(in: 0...0.9),
                duration: Double.random(in: 2.2...3.2),
                spin: Double.random(in: 70...160) * (Bool.random() ? 1 : -1),
                color: palette[index % palette.count],
                opacity: Double.random(in: 0.45...0.75)
            )
        }
        ripples = (0..<2).map { index in
            Ripple(
                id: index,
                delay: Double(index) * 0.45,
                duration: 2.0,
                endScale: 2.1 + CGFloat(index) * 0.5
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !reduceMotion {
                    ForEach(ripples) { ripple in
                        rippleRing(ripple)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
                    }

                    ForEach(petals) { petal in
                        petalView(petal, in: geo.size)
                    }
                }

                message
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // The flip itself is not animated; each element carries its own
            // `.animation(_:value:)` with its own curve and delay, which is
            // what staggers the ripples and petals off a single state change.
            hasBegun = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to Coppice Pro. Your quiet space is kept.")
    }

    // MARK: - Ripple

    private func rippleRing(_ ripple: Ripple) -> some View {
        Circle()
            .stroke(DesignSystem.Colors.sage.opacity(0.45), lineWidth: 1.25)
            .frame(width: 120, height: 120)
            .scaleEffect(hasBegun ? ripple.endScale : 0.35)
            .opacity(hasBegun ? 0 : 0.8)
            .animation(
                .easeOut(duration: ripple.duration).delay(ripple.delay),
                value: hasBegun
            )
    }

    // MARK: - Petals

    private func petalView(_ petal: Petal, in size: CGSize) -> some View {
        let startX = size.width * petal.xFraction
        let startY: CGFloat = -30
        let endY = size.height * petal.fallDistance

        return Capsule()
            .fill(petal.color)
            .frame(width: petal.width, height: petal.height)
            .rotationEffect(.degrees(hasBegun ? petal.spin : petal.spin * 0.1))
            .offset(
                x: hasBegun ? petal.drift : 0,
                y: hasBegun ? endY : startY
            )
            // Petals begin above the screen edge, so fading *out* over the
            // fall is the only opacity ramp needed — they never pop in.
            .opacity(hasBegun ? 0 : petal.opacity)
            .animation(
                .easeIn(duration: petal.duration).delay(petal.delay),
                value: hasBegun
            )
            .position(x: startX, y: 0)
    }

    // MARK: - Message

    private var message: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(DesignSystem.Colors.sage)

            Text("Your quiet space is kept.")
                .font(.system(size: 17, weight: .medium, design: .serif).italic())
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("Welcome to Coppice Pro")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textCase(.uppercase)
        }
        .opacity(hasBegun ? 1 : 0)
        .offset(y: hasBegun ? 0 : 8)
        .animation(.easeOut(duration: 0.9).delay(0.35), value: hasBegun)
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        ProCelebrationView()
    }
}
