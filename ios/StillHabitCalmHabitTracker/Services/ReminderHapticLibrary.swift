//
//  ReminderHapticLibrary.swift
//  StillHabitCalmHabitTracker
//
//  A signature vibration per habit, so a nudge can be recognized by feel alone
//  — pocket, wrist-down, phone face-down, sound off.
//
//  iOS does not let an app attach a custom vibration to a *delivered* local
//  notification (the system owns that haptic and ties it to the alert sound).
//  What an app can do is play its own Core Haptics pattern the moment the
//  reminder surfaces inside the app: when it lands as a banner while StillHabitCalmHabitTracker
//  is open, and when the user opens the app by tapping it. Both paths are wired
//  through `ReminderPresentationDelegate`, and the same pattern backs the live
//  preview in the reminder picker, so what you feel while choosing is exactly
//  what you'll feel later.
//
//  Devices without a Taptic Engine (and the simulator) fall back to a timed
//  sequence of `UIImpactFeedbackGenerator` hits that traces the same rhythm.
//

import Foundation
import CoreHaptics
import UIKit

/// The vibration signature a habit's reminder plays.
nonisolated enum ReminderHaptic: String, CaseIterable, Identifiable, Sendable {
    /// Two slow swells, like an inhale and an exhale — the app's default.
    case breath
    /// A double thump, paused, then repeated.
    case heartbeat
    /// One sharp tap dissolving into fading echoes.
    case ripple
    /// Three taps climbing in strength.
    case ascend
    /// Two crisp knocks, dry and immediate.
    case knock
    /// No vibration at all.
    case still

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breath: return "Breath"
        case .heartbeat: return "Heartbeat"
        case .ripple: return "Ripple"
        case .ascend: return "Ascend"
        case .knock: return "Knock"
        case .still: return "Still"
        }
    }

    var symbolName: String {
        switch self {
        case .breath: return "wind"
        case .heartbeat: return "waveform.path.ecg"
        case .ripple: return "dot.radiowaves.left.and.right"
        case .ascend: return "chart.bar.fill"
        case .knock: return "hand.tap"
        case .still: return "minus"
        }
    }

    /// One-line description of the rhythm, used by VoiceOver and the summary.
    var rhythmDescription: String {
        switch self {
        case .breath: return "Two slow swells"
        case .heartbeat: return "A double thump, twice"
        case .ripple: return "A tap that fades out"
        case .ascend: return "Three rising taps"
        case .knock: return "Two crisp knocks"
        case .still: return "No vibration"
        }
    }

    /// Resolves a stored raw value, defaulting to the app's breath rhythm so
    /// habits created before this setting existed still feel like StillHabitCalmHabitTracker.
    static func resolve(_ rawValue: String?) -> ReminderHaptic {
        guard let rawValue, let haptic = ReminderHaptic(rawValue: rawValue) else { return .breath }
        return haptic
    }
}

/// Plays reminder haptic signatures. A single shared instance keeps one warm
/// Core Haptics engine alive for the life of the app.
@MainActor
final class ReminderHapticLibrary {
    static let shared = ReminderHapticLibrary()

    /// One beat of a pattern. `duration == nil` is a transient tap; otherwise
    /// it's a continuous swell of that length.
    private struct Beat {
        let time: TimeInterval
        let intensity: Float
        let sharpness: Float
        var duration: TimeInterval?

        init(_ time: TimeInterval, intensity: Float, sharpness: Float, duration: TimeInterval? = nil) {
            self.time = time
            self.intensity = intensity
            self.sharpness = sharpness
            self.duration = duration
        }
    }

    private var engine: CHHapticEngine?
    /// Cancels an in-flight fallback sequence when a new preview starts.
    private var fallbackTask: Task<Void, Never>?

    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private init() {}

    // MARK: - Public

    /// Warms the haptic engine on launch so the first reminder is not delayed
    /// by engine start-up. Safe to call on hardware without a Taptic Engine.
    func prepare() {
        guard supportsHaptics else { return }
        _ = startedEngine()
    }

    /// Plays a signature once. Silently does nothing for `.still`, and degrades
    /// to a timed `UIImpactFeedbackGenerator` sequence when Core Haptics is
    /// unavailable so the rhythm still reads on older devices.
    func play(_ haptic: ReminderHaptic) {
        CrashDiagnostics.note("haptic \(haptic.rawValue)")
        fallbackTask?.cancel()
        fallbackTask = nil

        let beats = Self.beats(for: haptic)
        guard !beats.isEmpty else { return }

        if supportsHaptics, let engine = startedEngine(), playWithEngine(beats, on: engine) {
            return
        }
        playFallback(beats)
    }

    /// Resolves a raw value and plays it. Used by the notification delegate,
    /// which only ever sees the string stored in the notification payload.
    func play(rawValue: String?) {
        play(ReminderHaptic.resolve(rawValue))
    }

    // MARK: - Core Haptics

    /// Returns a running engine, creating and starting it on first use.
    /// Returns nil if the engine cannot be created or started.
    private func startedEngine() -> CHHapticEngine? {
        if let engine { return engine }
        do {
            let created = try CHHapticEngine()
            // The system stops the engine when the app backgrounds or on an
            // audio-session interruption; drop it so the next play restarts it.
            created.stoppedHandler = { _ in
                Task { @MainActor [weak self] in self?.engine = nil }
            }
            created.resetHandler = { [weak created] in
                try? created?.start()
            }
            try created.start()
            engine = created
            return created
        } catch {
            print("ReminderHapticLibrary: haptic engine unavailable — \(error.localizedDescription)")
            engine = nil
            return nil
        }
    }

    /// Builds and plays a pattern. Returns false so the caller can fall back.
    private func playWithEngine(_ beats: [Beat], on engine: CHHapticEngine) -> Bool {
        let events: [CHHapticEvent] = beats.map { beat in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness),
            ]
            if let duration = beat.duration {
                return CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: parameters,
                    relativeTime: beat.time,
                    duration: duration
                )
            }
            return CHHapticEvent(
                eventType: .hapticTransient,
                parameters: parameters,
                relativeTime: beat.time
            )
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            print("ReminderHapticLibrary: could not play pattern — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fallback

    /// Traces the same rhythm with impact generators, which every device that
    /// vibrates at all supports.
    private func playFallback(_ beats: [Beat]) {
        fallbackTask = Task { @MainActor in
            var elapsed: TimeInterval = 0
            for beat in beats {
                let wait = beat.time - elapsed
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    if Task.isCancelled { return }
                }
                elapsed = beat.time

                let style: UIImpactFeedbackGenerator.FeedbackStyle
                switch beat.sharpness {
                case ..<0.3: style = .soft
                case ..<0.6: style = .medium
                default: style = .rigid
                }
                let generator = UIImpactFeedbackGenerator(style: style)
                generator.prepare()
                generator.impactOccurred(intensity: CGFloat(beat.intensity))
            }
        }
    }

    // MARK: - Patterns

    /// The rhythm behind each signature. Every pattern stays under a second and
    /// a half so a reminder never feels like an alarm.
    private static func beats(for haptic: ReminderHaptic) -> [Beat] {
        switch haptic {
        case .breath:
            return [
                Beat(0, intensity: 0.55, sharpness: 0.12, duration: 0.45),
                Beat(0.62, intensity: 0.42, sharpness: 0.08, duration: 0.55),
            ]
        case .heartbeat:
            return [
                Beat(0, intensity: 0.85, sharpness: 0.45),
                Beat(0.16, intensity: 0.55, sharpness: 0.30),
                Beat(0.60, intensity: 0.85, sharpness: 0.45),
                Beat(0.76, intensity: 0.55, sharpness: 0.30),
            ]
        case .ripple:
            return [
                Beat(0, intensity: 0.90, sharpness: 0.70),
                Beat(0.13, intensity: 0.60, sharpness: 0.50),
                Beat(0.25, intensity: 0.38, sharpness: 0.36),
                Beat(0.35, intensity: 0.22, sharpness: 0.24),
                Beat(0.43, intensity: 0.12, sharpness: 0.16),
            ]
        case .ascend:
            return [
                Beat(0, intensity: 0.32, sharpness: 0.25),
                Beat(0.18, intensity: 0.58, sharpness: 0.45),
                Beat(0.36, intensity: 0.95, sharpness: 0.70),
            ]
        case .knock:
            return [
                Beat(0, intensity: 1.0, sharpness: 0.95),
                Beat(0.13, intensity: 0.85, sharpness: 0.95),
            ]
        case .still:
            return []
        }
    }
}
