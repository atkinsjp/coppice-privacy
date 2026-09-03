//
//  StillTactileWave.swift
//  CoppiceHabitsThatRest
//
//  The signature CoppiceHabitsThatRest tactile interaction.
//  Press: the surface settles down to 0.97 on a snappy spring.
//  Release: a medium haptic pulse and a soft ripple ring that travels
//  outward from the surface, like water.
//
//  Two rules keep this cheap enough to attach to *every* control in the app
//  (the 90-day heatmap alone renders ninety of them):
//
//  1. **No offscreen render passes.** The ring used to be drawn with
//     `.blur(radius:)`, which forces Core Animation to allocate an offscreen
//     buffer per ripple. On the cloud simulator those allocations go through a
//     sandbox that already reports `IOSurfaceClientSetSurfaceNotify failed`,
//     and a failed surface allocation aborts the process from inside Core
//     Animation — a SIGABRT with no Swift frames. Softness now comes from
//     layered strokes with falling opacity, which composite in place.
//
//  2. **Nothing is attached while idle.** The overlay (and its
//     `GeometryReader`) only exists while a ripple is actually animating, so a
//     screen full of buttons costs nothing until one is pressed.
//

import SwiftUI
import UIKit

// MARK: - Shared haptics

/// One prepared impact generator for the whole app. Allocating a fresh
/// `UIImpactFeedbackGenerator` per press (and there is one per button, per tap)
/// churns the Taptic client connection for no benefit.
@MainActor
private enum TactileHaptics {
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static func mediumTap() {
        medium.impactOccurred()
        medium.prepare()
    }
}

// MARK: - Ripple model

private struct TactileRipple: Identifiable, Equatable {
    let id = UUID()
    let center: CGPoint
}

// MARK: - A single expanding ring

/// Three concentric strokes with falling opacity read as one soft, diffused
/// ring — the same visual as a blur, without the offscreen buffer.
private struct TactileRippleRing: View {
    let accent: Color
    let diameter: CGFloat

    @State private var isExpanding = false

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.20), lineWidth: 7)
            Circle().stroke(accent.opacity(0.45), lineWidth: 4)
            Circle().stroke(accent.opacity(0.85), lineWidth: 1.5)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isExpanding ? 1.4 : 0.1)
        .opacity(isExpanding ? 0 : 0.85)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                isExpanding = true
            }
        }
    }
}

// MARK: - Ripple layer

private struct TactileRippleOverlay: View {
    let ripples: [TactileRipple]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let diameter = max(geo.size.width, geo.size.height)
            ForEach(ripples) { ripple in
                TactileRippleRing(accent: accent, diameter: diameter)
                    .position(resolvedCenter(for: ripple, in: geo.size))
            }
        }
        .allowsHitTesting(false)
    }

    /// Falls back to the visual center when no touch point was captured.
    private func resolvedCenter(for ripple: TactileRipple, in size: CGSize) -> CGPoint {
        ripple.center == .zero
            ? CGPoint(x: size.width / 2, y: size.height / 2)
            : ripple.center
    }
}

// MARK: - Ripple bookkeeping

/// Keeps at most a couple of rings alive at once. A user hammering a control
/// (or a heatmap cell) could otherwise stack dozens of animating layers.
private func appendRipple(_ ripple: TactileRipple, to ripples: inout [TactileRipple]) {
    ripples.append(ripple)
    if ripples.count > 3 {
        ripples.removeFirst(ripples.count - 3)
    }
}

// MARK: - Button style

/// CoppiceHabitsThatRest's signature fluid button style: 0.97 press-scale on a
/// snappy spring, a medium haptic pulse at the instant of release,
/// and an outward water-ripple ring.
struct StillTactileWaveButtonStyle: ButtonStyle {
    var accent: Color = DesignSystem.Colors.sage

    func makeBody(configuration: Configuration) -> some View {
        TactileWaveBody(configuration: configuration, accent: accent)
    }
}

private struct TactileWaveBody: View {
    let configuration: ButtonStyleConfiguration
    let accent: Color

    @State private var ripples: [TactileRipple] = []
    @State private var touchLocation: CGPoint = .zero

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .overlay {
                // Only materialize the ripple layer (and its GeometryReader)
                // while something is actually animating.
                if !ripples.isEmpty {
                    TactileRippleOverlay(ripples: ripples, accent: accent)
                }
            }
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                guard wasPressed, !isPressed else { return }
                TactileHaptics.mediumTap()
                spawnRipple(at: touchLocation)
            }
    }

    private func spawnRipple(at point: CGPoint) {
        let ripple = TactileRipple(center: point)
        appendRipple(ripple, to: &ripples)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

extension ButtonStyle where Self == StillTactileWaveButtonStyle {
    /// `.buttonStyle(.stillTactileWave(accent:))`
    static func stillTactileWave(accent: Color = DesignSystem.Colors.sage) -> StillTactileWaveButtonStyle {
        StillTactileWaveButtonStyle(accent: accent)
    }
}

// MARK: - Quiet press style (dense grids)

/// A featherweight alternative for surfaces that appear by the dozen — the
/// 90-day heatmap, colour swatch grids. Same tactile language (press-scale +
/// haptic), no per-cell ripple layer.
struct StillQuietPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.88

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                guard wasPressed, !isPressed else { return }
                TactileHaptics.mediumTap()
            }
    }
}

extension ButtonStyle where Self == StillQuietPressStyle {
    /// `.buttonStyle(.stillQuietPress)` — for dense grids of small controls.
    static var stillQuietPress: StillQuietPressStyle { StillQuietPressStyle() }
}

// MARK: - View modifier (for gesture-driven surfaces like habit cards)

/// Fires the signature ripple + haptic whenever `trigger` changes.
struct StillTactileWaveModifier<Trigger: Equatable>: ViewModifier {
    let accent: Color
    let trigger: Trigger
    var playsHaptic: Bool = true

    @State private var ripples: [TactileRipple] = []
    @State private var touchLocation: CGPoint = .zero

    func body(content: Content) -> some View {
        content
            .overlay {
                if !ripples.isEmpty {
                    TactileRippleOverlay(ripples: ripples, accent: accent)
                }
            }
            .onChange(of: trigger) { _, _ in
                if playsHaptic {
                    TactileHaptics.mediumTap()
                }
                spawnRipple(at: touchLocation)
            }
    }

    private func spawnRipple(at point: CGPoint) {
        let ripple = TactileRipple(center: point)
        appendRipple(ripple, to: &ripples)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

extension View {
    /// Attaches the CoppiceHabitsThatRest tactile wave to a non-Button surface.
    /// A ripple (and optional medium haptic) fires whenever `trigger` changes.
    func tactileWave(accent: Color, trigger: some Equatable, playsHaptic: Bool = true) -> some View {
        modifier(StillTactileWaveModifier(accent: accent, trigger: trigger, playsHaptic: playsHaptic))
    }
}
