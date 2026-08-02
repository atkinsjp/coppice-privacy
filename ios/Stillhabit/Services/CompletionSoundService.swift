//
//  CompletionSoundService.swift
//  Stillhabit
//
//  A soft, short chime that plays the instant any habit is marked complete —
//  a gentle two-note whisper (a perfect fifth) with a quick exponential decay,
//  fading to silence in under a second. It complements but never competes with
//  the longer "Still Moment" singing-bowl reward that fires when the day's
//  final habit is completed.
//
//  IMPORTANT: Like StillMomentService, this deliberately avoids AVFoundation
//  entirely — no AVAudioSession, no AVAudioEngine, no AVAudioPlayer. On the
//  iOS 26 simulator, AVAudioSession.setActive(true) can abort() internally
//  in C++ audio-session code, outside any Swift do-catch, producing a
//  SIGABRT with no recoverable error. Instead, the chime is synthesized as
//  raw PCM samples (pure Swift math), written to a temporary WAV file
//  manually (RIFF/WAVE header — no AVFoundation), and played through
//  AudioTool's AudioServicesPlaySystemSound, which requires no audio session,
//  respects the silent switch, and degrades silently on any failure.
//

import Foundation
import AudioToolbox

/// Synthesizes and plays the soft per-habit completion chime.
///
/// A single shared instance owns the rendered WAV and its AudioToolbox sound
/// ID. Every habit card used to hold its own service, which meant a dozen
/// instances deleting and rewriting the *same* temporary file — and disposing
/// each other's sound IDs as rows scrolled in and out of the lazy stack.
final class CompletionSoundService {
    /// The one chime for the whole app.
    static let shared = CompletionSoundService()

    private static let sampleRate: Int = 44100
    private static let duration: Double = 0.9

    /// The cached system sound ID of the rendered chime. Built lazily on first
    /// play so no AudioTool resources are touched during SwiftUI view construction.
    private var cachedSoundID: SystemSoundID = 0
    private var hasRendered: Bool = false

    private init() {
        // Intentionally empty — all audio work is deferred to the first
        // playChime() call so view construction never touches the audio stack.
    }

    deinit {
        if cachedSoundID != 0 {
            AudioServicesDisposeSystemSoundID(cachedSoundID)
        }
    }

    /// Plays the completion chime once. Safe to call repeatedly. If the chime
    /// can't be rendered or loaded, the call degrades to silence — it never aborts.
    func playChime() {
        guard ensureChimeSound() else { return }
        CrashDiagnostics.note("completion chime")
        AudioServicesPlaySystemSound(cachedSoundID)
    }

    // MARK: - Private

    /// Renders the synthesized chime to a temporary WAV file (if not already
    /// cached) and loads it as a system sound. Returns false (silently) if
    /// the file can't be written or the sound can't be loaded.
    private func ensureChimeSound() -> Bool {
        if hasRendered, cachedSoundID != 0 { return true }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stillhabit_completion.wav")

        // Written atomically, so an existing file is always complete and can
        // be reused rather than deleted out from under AudioToolbox.
        if !FileManager.default.fileExists(atPath: url.path) {
            guard writeChimeWAV(to: url) else { return false }
        }

        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == noErr, soundID != 0 else { return false }

        cachedSoundID = soundID
        hasRendered = true
        return true
    }

    // MARK: - WAV file writing (no AVFoundation)

    /// Writes the synthesized chime to a WAV file at the given URL using a
    /// manual RIFF/WAVE header + 16-bit PCM data. Returns false on any failure.
    private func writeChimeWAV(to url: URL) -> Bool {
        let samples = synthesizeChimeSamples()
        guard !samples.isEmpty else { return false }

        let dataByteCount = samples.count * 2
        let fileSize = UInt32(4 + 24 + 8 + dataByteCount)

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(fileSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(Self.sampleRate).littleEndianData)
        data.append(UInt32(Self.sampleRate * 2).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)

        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataByteCount).littleEndianData)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intVal = Int16(clamped * 32767)
            data.append(intVal.littleEndianData)
        }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    /// Renders a gentle two-note whisper — a low fundamental (E4) joined a
    /// moment later by its perfect fifth (B4) — with a quick exponential
    /// decay so the whole chime fades to silence in under a second. A short
    /// attack avoids any click; the second note enters softly at ~80ms so
    /// the interval reads as a single, settled gesture rather than two
    /// separate plinks. Returns an array of Float samples in [-1, 1].
    private func synthesizeChimeSamples() -> [Float] {
        let frameCount = Int(Double(Self.sampleRate) * Self.duration)
        guard frameCount > 0 else { return [] }

        // (frequency Hz, relative amplitude, per-partial decay seconds, enter-at seconds)
        let partials: [(freq: Double, amp: Double, decay: Double, enter: Double)] = [
            (329.63, 0.85, 0.55, 0.0),   // E4 — fundamental, immediate
            (493.88, 0.55, 0.45, 0.08),  // B4 — perfect fifth, soft delayed entrance
        ]

        let twoPi = 2.0 * Double.pi
        let sampleRateDouble = Double(Self.sampleRate)
        var samples = [Float]()
        samples.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRateDouble
            let attack = min(1.0, t / 0.008)
            let overallDecay = exp(-t / 0.32)
            var sample = 0.0
            for p in partials {
                guard t >= p.enter else { continue }
                let localT = t - p.enter
                let localAttack = min(1.0, localT / 0.006)
                sample += p.amp * localAttack * exp(-localT / p.decay) * sin(twoPi * p.freq * localT)
            }
            // Keep it subtle — a whisper, never louder than a soft breath.
            samples.append(Float(sample * attack * overallDecay * 0.28))
        }
        return samples
    }
}

// MARK: - Little-endian byte helpers

private extension UInt16 {
    var littleEndianData: Data {
        Data([UInt8(truncatingIfNeeded: self), UInt8(truncatingIfNeeded: self >> 8)])
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        Data([
            UInt8(truncatingIfNeeded: self),
            UInt8(truncatingIfNeeded: self >> 8),
            UInt8(truncatingIfNeeded: self >> 16),
            UInt8(truncatingIfNeeded: self >> 24),
        ])
    }
}

private extension Int16 {
    var littleEndianData: Data {
        Data([UInt8(truncatingIfNeeded: self), UInt8(truncatingIfNeeded: self >> 8)])
    }
}
