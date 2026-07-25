//
//  StillMomentService.swift
//  Stillhabit
//
//  The "Still Moment" audio reward. When the user marks their final scheduled
//  habit for the day complete, this service plays a soft, resonant chime that
//  evokes a Tibetan singing bowl — a low fundamental layered with slightly
//  inharmonic partials and a slow exponential decay, fading to silence over
//  ~3.5 seconds.
//
//  The chime is synthesized up front into a PCM buffer, then written to a
//  temporary WAV file and played through a standard AVAudioPlayer — the same
//  stable playback path the ambient loops use. We deliberately avoid
//  AVAudioEngine + AVAudioPlayerNode here because that graph is flaky on the
//  iOS simulator and can abort internally in the audio render thread, even
//  when engine.start() is wrapped in do-catch. AVAudioPlayer has no such
//  render thread and degrades cleanly to silence on any failure.
//
//  The session uses `.ambient` + `.mixWithOthers` so the chime respects the
//  silent switch and blends politely with any active ambient loop, never
//  interrupting other audio. Nothing here is loud or harsh — the whole point
//  is a gentle, grounding resolution to the day.
//

import Foundation
import AVFoundation

/// Synthesizes and plays the soft "Still Moment" singing-bowl chime.
final class StillMomentService {

    private static let sampleRate: Double = 44100
    private static let duration: Double = 3.5

    /// The cached URL of the rendered WAV file. Built lazily on first play so
    /// no AVFoundation resources are touched during SwiftUI view construction.
    private var cachedChimeURL: URL?
    private var player: AVAudioPlayer?

    init() {
        // Intentionally empty — all AVFoundation work is deferred to the first
        // playChime() call so view construction never touches the audio stack.
    }

    deinit {
        player?.stop()
    }

    /// Plays the chime once, interrupting any still-sounding previous play.
    /// Safe to call repeatedly. If the audio session can't be configured, the
    /// WAV can't be rendered, or the player can't start, the call degrades to
    /// silence — it never aborts.
    func playChime() {
        configureSession()
        guard let url = ensureChimeFile() else { return }
        do {
            // Stop and replace any existing player so a new play always starts
            // from the beginning of the chime.
            player?.stop()
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.volume = 0.9
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            // Non-fatal: the chime simply won't be audible.
            player = nil
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

    /// Renders the synthesized chime to a temporary WAV file the first time it
    /// is needed, then caches the URL for every subsequent play. Returns nil
    /// (silently) if the file can't be written.
    private func ensureChimeFile() -> URL? {
        if let cachedChimeURL { return cachedChimeURL }
        guard let buffer = synthesizeChime() else { return nil }
        guard let url = writeChimeWAV(from: buffer) else { return nil }
        cachedChimeURL = url
        return url
    }

    /// Renders a gentle, resonant chord with a slow exponential decay — a low
    /// fundamental plus slightly inharmonic partials to evoke the warm,
    /// beating character of a Tibetan singing bowl. A short attack avoids any
    /// click, and an overall decay term shapes the long, soft fade.
    private func synthesizeChime() -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: 1
        )
        guard let format else { return nil }

        let frameCount = AVAudioFrameCount(Self.sampleRate * Self.duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return buffer }

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
        return buffer
    }

    /// Writes the synthesized PCM buffer to a temporary WAV file and returns
    /// its URL. Uses AVAudioFile so the header is written correctly. Returns
    /// nil on any failure — the caller degrades to silence.
    private func writeChimeWAV(from buffer: AVAudioPCMBuffer) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stillhabit_chime.wav")
        // Remove any stale render so the file is always fresh.
        try? FileManager.default.removeItem(at: url)
        guard let format = buffer.format as? AVAudioFormat else { return nil }
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings
            )
            try file.write(from: buffer)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
