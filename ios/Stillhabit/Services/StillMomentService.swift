//
//  StillMomentService.swift
//  Stillhabit
//
//  The "Still Moment" audio reward. When the user marks their final scheduled
//  habit for the day complete, this service plays a soft, resonant chime that
//  evokes a Tibetan singing bowl — a low fundamental layered with slightly
//  inharmonic partials and a slow exponential decay, fading to silence over
//  ~3.5 seconds. The chime is synthesized at runtime from a short PCM buffer
//  (no bundled asset needed) and played through an AVAudioEngine player node.
//
//  The session uses `.ambient` + `.mixWithOthers` so the chime respects the
//  silent switch and blends politely with any active ambient loop, never
//  interrupting other audio. Nothing here is loud or harsh — the whole point
//  is a gentle, grounding resolution to the day.
//
//  The AVAudioEngine + player node are created lazily on the first play and
//  never touch AVFoundation during SwiftUI view initialization. All playback
//  is guarded on the engine actually running, so a failure to start the
//  engine (simulator audio session contention, sandbox denials, etc.) degrades
//  to silence instead of aborting.
//

import Foundation
import AVFoundation

/// Synthesizes and plays the soft "Still Moment" singing-bowl chime.
final class StillMomentService {

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let format: AVAudioFormat = AVAudioFormat(
        standardFormatWithSampleRate: StillMomentService.sampleRate,
        channels: 1
    )!

    private static let sampleRate: Double = 44100
    private static let duration: Double = 3.5

    private var chimeBuffer: AVAudioPCMBuffer?
    private var isEngineStarted = false

    init() {
        // Only the PCM buffer is rendered up front — it's cheap and pure.
        // The AVAudioEngine graph is deferred to the first play so no
        // AVFoundation resources are held (or initialized) during SwiftUI
        // view construction.
        chimeBuffer = synthesizeChime()
    }

    deinit {
        // Best-effort teardown. Tearing down on the main thread is safe;
        // never touch AVAudioEngine off-main.
        if let player, player.isPlaying {
            player.stop()
        }
        if let engine, engine.isRunning {
            engine.stop()
        }
    }

    /// Plays the chime once, interrupting any still-sounding previous play.
    /// Safe to call repeatedly. If the audio session can't be configured or
    /// the engine can't start, the call degrades to silence — it never aborts.
    func playChime() {
        guard let buffer = chimeBuffer else { return }
        configureSession()
        let engine = ensureEngine()
        guard startEngineIfNeeded(engine) else { return }
        guard let player else { return }

        player.scheduleBuffer(buffer, at: nil, options: [.interrupts]) { [weak self] in
            // Stop the player before the engine, then release the engine so it
            // doesn't idle-run between rare plays. Always on the main thread.
            DispatchQueue.main.async {
                guard let self else { return }
                self.player?.stop()
                if self.engine?.isRunning == true {
                    self.engine?.stop()
                }
                self.isEngineStarted = false
            }
        }
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Private

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal: the chime simply won't be audible.
        }
    }

    /// Lazily builds the AVAudioEngine graph on first use. Returns the shared
    /// engine, creating + attaching the player node if needed.
    private func ensureEngine() -> AVAudioEngine {
        if let engine { return engine }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.player = player
        return engine
    }

    /// Starts the engine if it isn't already running. Returns true only when
    /// the engine is actually running — callers must guard playback on this.
    private func startEngineIfNeeded(_ engine: AVAudioEngine) -> Bool {
        if engine.isRunning {
            isEngineStarted = true
            return true
        }
        do {
            try engine.start()
            isEngineStarted = true
            return true
        } catch {
            isEngineStarted = false
            return false
        }
    }

    /// Renders a gentle, resonant chord with a slow exponential decay — a low
    /// fundamental plus slightly inharmonic partials to evoke the warm,
    /// beating character of a Tibetan singing bowl. A short attack avoids any
    /// click, and an overall decay term shapes the long, soft fade.
    private func synthesizeChime() -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(Self.sampleRate * Self.duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        buffer?.frameLength = frameCount
        guard let data = buffer?.floatChannelData?[0] else { return buffer! }

        // (frequency Hz, relative amplitude, per-partial decay seconds)
        let partials: [(freq: Double, amp: Double, decay: Double)] = [
            (196.00, 1.00, 2.8),  // G3 — fundamental
            (294.66, 0.55, 2.2),  // D4 — perfect fifth
            (392.00, 0.32, 1.7),  // G4 — octave
            (493.88, 0.18, 1.3),  // B4 — major third
            (587.33, 0.10, 1.0),  // D5 — fifth, a whisper on top
        ]

        let n = Int(frameCount)
        for i in 0..<n {
            let t = Double(i) / Self.sampleRate
            let attack = min(1.0, t / 0.015)
            let overallDecay = exp(-t / 1.8)
            var sample = 0.0
            for p in partials {
                sample += p.amp * exp(-t / p.decay) * sin(2.0 * Double.pi * p.freq * t)
            }
            // Keep the whole thing gentle — never louder than a soft breath.
            data[i] = Float(sample * attack * overallDecay * 0.22)
        }
        return buffer!
    }
}
