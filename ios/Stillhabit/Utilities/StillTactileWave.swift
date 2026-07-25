//
//  StillTactileWave.swift
//  Stillhabit
//
//  The signature Stillhabit tactile interaction.
//  Press: the surface settles down to 0.97 on a snappy spring.
//  Release: a medium haptic pulse and a soft, blurred ripple ring
//  that travels outward from the exact touch point, like water.
//

import SwiftUI

// MARK: - Ripple model

private struct TactileRipple: Identifiable, Equatable {
    let id = UUID()
    let center: CGPoint
}

// MARK: - A single expanding ring

private struct TactileRippleRing: View {
    let accent: Color
    let diameter: CGFloat

    @State private var isExpanding = false

    var body: some View {
        Circle()
            .stroke(accent, lineWidth: 4)
            .blur(radius: 2.5)
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

// MARK: - Button style

/// Stillhabit's signature fluid button style: 0.97 press-scale on a
/// snappy spring, a medium haptic pulse at the instant of release,
/// and an outward water-ripple ring from the touch point.
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
            .overlay(TactileRippleOverlay(ripples: ripples, accent: accent))
            .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                guard wasPressed, !isPressed else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                spawnRipple(at: touchLocation)
            }
    }

    private func spawnRipple(at point: CGPoint) {
        let ripple = TactileRipple(center: point)
        ripples.append(ripple)
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

// MARK: - View modifier (for gesture-driven surfaces like habit cards)

/// Fires the signature ripple + haptic whenever `trigger` changes.
/// The ripple originates from the last known touch point on the surface.
struct StillTactileWaveModifier<Trigger: Equatable>: ViewModifier {
    let accent: Color
    let trigger: Trigger
    var playsHaptic: Bool = true

    @State private var ripples: [TactileRipple] = []
    @State private var touchLocation: CGPoint = .zero

    func body(content: Content) -> some View {
        content
            .overlay(TactileRippleOverlay(ripples: ripples, accent: accent))
            .onChange(of: trigger) { _, _ in
                if playsHaptic {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                spawnRipple(at: touchLocation)
            }
    }

    private func spawnRipple(at point: CGPoint) {
        let ripple = TactileRipple(center: point)
        ripples.append(ripple)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

extension View {
    /// Attaches the Stillhabit tactile wave to a non-Button surface.
    /// A ripple (and optional medium haptic) fires whenever `trigger` changes.
    func tactileWave(accent: Color, trigger: some Equatable, playsHaptic: Bool = true) -> some View {
        modifier(StillTactileWaveModifier(accent: accent, trigger: trigger, playsHaptic: playsHaptic))
    }
}
