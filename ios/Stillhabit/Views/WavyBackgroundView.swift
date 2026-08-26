//
//  WavyBackgroundView.swift
//  Stillhabit
//
//  A slowly drifting, earthy backdrop. Moss, taupe, and a whisper of
//  terracotta ebb and flow like light moving across a wall — quiet enough
//  to never compete with content.
//
//  Rendering notes (this is load-bearing, not decoration):
//
//  The first version of this view was a 4×4 `MeshGradient` re-rasterized 12
//  times a second by a `TimelineView`. `MeshGradient` is drawn by SwiftUI's
//  Metal renderer, which needs a fresh render target every frame. This app
//  runs in a sandbox where `IOSurfaceRoot` access is denied — the launch log
//  says so on every single run:
//
//      IOSurfaceClientSetSurfaceNotify failed e00002c7
//      IOServiceOpen(IOSurfaceRoot) returned kr=0xe00002e2 (DENIED)
//
//  A failed surface allocation inside Core Animation calls `abort()`, which
//  surfaces as a bare SIGABRT with no Swift frames and no reason — exactly the
//  shape of the crash reports this app has been producing, at unpredictable
//  points deep into a session and never at launch. The risk peaks whenever the
//  render target is rebuilt: presenting or dismissing a sheet, returning from
//  the background.
//
//  So the mesh is gone. The same visual is now built from plain gradient
//  layers, which composite in place with no offscreen buffer and no Metal
//  pass, and the drift is a `repeatForever` Core Animation running entirely on
//  the render server — zero per-frame CPU, zero re-rasterization, nothing to
//  pause. There is deliberately no `.blur()` anywhere here: blur is the other
//  modifier that forces an offscreen allocation. Softness comes from gradients
//  that fade to clear.
//

import SwiftUI

/// The signature animated backdrop for the Today view.
struct WavyBackgroundView: View {
    /// When true, a warm golden/ochre glow gently pulses and expands outward
    /// over ~3 seconds — the visual half of the "Still Moment" reward that
    /// fires when every scheduled habit for the day is complete. The glow
    /// lives at the background layer (behind all content) so it never
    /// interferes with touch targets.
    var warmGlow: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped once on appear; each blob eases between its two extremes
    /// forever after. The animation lives on the render server, so this costs
    /// nothing once it has started.
    @State private var isDrifting = false

    var body: some View {
        // The base color is the layout anchor: it accepts whatever size the
        // parent proposes. The blobs are painted in an overlay so their large
        // fixed frames (up to 600pt) never inflate this view's layout size —
        // as ZStack children they once did, which made containing views
        // (like the paywall) wider than the screen and clipped their content
        // on both edges.
        baseColor
            .overlay {
                ForEach(blobs) { blob in
                    blobLayer(blob)
                }
            }
            .overlay {
                if warmGlow {
                    WarmGlowPulse(reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                isDrifting = true
            }
    }

    // MARK: - Layers

    private func blobLayer(_ blob: DriftBlob) -> some View {
        let travelling = isDrifting && !reduceMotion
        return EllipticalGradient(
            colors: [blob.color, blob.color.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.55
        )
        .frame(width: blob.size.width, height: blob.size.height)
        .offset(
            x: blob.origin.x + (travelling ? blob.travel.width : -blob.travel.width),
            y: blob.origin.y + (travelling ? blob.travel.height : -blob.travel.height)
        )
        .animation(
            .easeInOut(duration: blob.duration)
                .repeatForever(autoreverses: true)
                .delay(blob.delay),
            value: isDrifting
        )
        .allowsHitTesting(false)
    }

    // MARK: - Palette

    private var isDark: Bool { colorScheme == .dark }

    /// Warm ivory in light mode, deep matte charcoal in dark mode — the same
    /// base the rest of the design system sits on.
    private var baseColor: Color {
        Color(hex: isDark ? "1C1E1D" : "F7F6F2")
    }

    /// Four soft washes of colour, each drifting on its own slow cycle. Sizes
    /// are generous so their edges always fall outside the screen and the
    /// gradient reads as ambient light rather than as four visible circles.
    private var blobs: [DriftBlob] {
        if isDark {
            return [
                DriftBlob(
                    id: 0,
                    color: Color(hex: "27302A").opacity(0.95),
                    size: CGSize(width: 520, height: 560),
                    origin: CGPoint(x: -120, y: -230),
                    travel: CGSize(width: 26, height: 34),
                    duration: 17,
                    delay: 0
                ),
                DriftBlob(
                    id: 1,
                    color: Color(hex: "2C2621").opacity(0.90),
                    size: CGSize(width: 560, height: 520),
                    origin: CGPoint(x: 150, y: -60),
                    travel: CGSize(width: -30, height: 24),
                    duration: 21,
                    delay: 1.4
                ),
                DriftBlob(
                    id: 2,
                    color: Color(hex: "232821").opacity(0.95),
                    size: CGSize(width: 480, height: 500),
                    origin: CGPoint(x: -100, y: 240),
                    travel: CGSize(width: 34, height: -28),
                    duration: 19,
                    delay: 2.6
                ),
                DriftBlob(
                    id: 3,
                    color: Color(hex: "24282A").opacity(0.85),
                    size: CGSize(width: 600, height: 560),
                    origin: CGPoint(x: 130, y: 330),
                    travel: CGSize(width: -24, height: -30),
                    duration: 23,
                    delay: 0.8
                ),
            ]
        }
        return [
            DriftBlob(
                id: 0,
                color: Color(hex: "DCE7D6").opacity(0.85),
                size: CGSize(width: 520, height: 560),
                origin: CGPoint(x: -120, y: -230),
                travel: CGSize(width: 26, height: 34),
                duration: 17,
                delay: 0
            ),
            DriftBlob(
                id: 1,
                color: Color(hex: "EFE7DA").opacity(0.90),
                size: CGSize(width: 560, height: 520),
                origin: CGPoint(x: 150, y: -60),
                travel: CGSize(width: -30, height: 24),
                duration: 21,
                delay: 1.4
            ),
            DriftBlob(
                id: 2,
                color: Color(hex: "F2DFD2").opacity(0.72),
                size: CGSize(width: 480, height: 500),
                origin: CGPoint(x: -100, y: 240),
                travel: CGSize(width: 34, height: -28),
                duration: 19,
                delay: 2.6
            ),
            DriftBlob(
                id: 3,
                color: Color(hex: "E6EAE3").opacity(0.85),
                size: CGSize(width: 600, height: 560),
                origin: CGPoint(x: 130, y: 330),
                travel: CGSize(width: -24, height: -30),
                duration: 23,
                delay: 0.8
            ),
        ]
    }
}

/// One drifting wash of colour in the backdrop.
private struct DriftBlob: Identifiable {
    let id: Int
    let color: Color
    let size: CGSize
    let origin: CGPoint
    /// Half the distance travelled; the blob eases between `-travel` and `+travel`.
    let travel: CGSize
    let duration: Double
    let delay: Double
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
/// let the earthy backdrop return to its resting state. Rendered inside the
/// background layer so it stays behind all foreground content and never
/// captures touches.
private struct WarmGlowPulse: View {
    let reduceMotion: Bool

    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0
    @State private var fadeTask: Task<Void, Never>?

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
        .onDisappear { fadeTask?.cancel() }
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
        fadeTask = Task {
            try? await Task.sleep(for: .seconds(0.95))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 2.25)) {
                opacity = 0
            }
        }
    }
}
