//
//  StillMomentService.swift
//  CoppiceHabitsThatRest
//
//  The "Coppice Moment" audio reward. When the user marks their final scheduled
//  habit for the day complete, this service plays a soft, resonant chime that
//  evokes a Tibetan singing bowl — a low fundamental layered with slightly
//  inharmonic partials and a slow exponential decay, fading to silence over
//  ~3.5 seconds.
//
//  IMPORTANT: This service deliberately avoids AVFoundation entirely — no
//  AVAudioSession, no AVAudioEngine, no AVAudioPlayer, no AVAudioFile. On the
//  iOS 26 simulator, AVAudioSession.setActive(true) can abort() internally
//  in C++ audio-session code, outside any Swift do-catch, producing a SIGABRT
//  with no recoverable error. Three consecutive preview crashes all shared the
//  same PC address, confirming a deterministic abort in a system audio function.
//
//  Instead, the chime is synthesized as raw PCM samples (pure Swift math),
//  written to a temporary WAV file manually (RIFF/WAVE header — no AVFoundation),
//  and played through AudioTool's AudioServicesPlaySystemSound, which:
//    • Requires no audio session configuration
//    • Respects the silent switch automatically
//    • Has no render thread that can abort
//    • Degrades silently on any failure
//

import Foundation
import AudioToolbox

/// Synthesizes and plays the soft "Coppice Moment" singing-bowl chime.
///
/// A single shared instance owns the rendered WAV and its AudioToolbox sound
/// ID, so the file is written exactly once per launch and never deleted while
/// another instance might still be pointing at it.
final class StillMomentService {
    /// The one singing bowl for the whole app.
    static let shared = StillMomentService()

    private static let sampleRate: Int = 44100
    private static let duration: Double = 3.5

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

    /// Plays the chime once. Safe to call repeatedly. If the chime can't be
    /// rendered or loaded, the call degrades to silence — it never aborts.
    func playChime() {
        guard ensureChimeSound() else { return }
        CrashDiagnostics.note("coppice moment chime")
        AudioServicesPlaySystemSound(cachedSoundID)
    }

    // MARK: - Private

    /// Renders the synthesized chime to a temporary WAV file (if not already
    /// cached) and loads it as a system sound. Returns false (silently) if
    /// the file can't be written or the sound can't be loaded.
    private func ensureChimeSound() -> Bool {
        if hasRendered, cachedSoundID != 0 { return true }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stillhabit_chime.wav")

        // Written atomically, so an existing file is always complete and can
        // be reused rather than deleted out from under AudioToolbox.
        if !FileManager.default.fileExists(atPath: url.path) {
            guard writeChimeWAV(to: url) else { return false }
        }

        // Load the WAV file as a system sound. AudioServicesCreateSystemSoundID
        // is a pure C API with no session configuration and no render thread.
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

        // RIFF/WAVE header for 16-bit PCM, mono, 44100 Hz.
        let dataByteCount = samples.count * 2  // int16 = 2 bytes per sample
        let fileSize = UInt32(4 + 24 + 8 + dataByteCount)  // "WAVE" + fmt + data header + data

        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(fileSize).littleEndianData)
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)          // chunk size
        data.append(UInt16(1).littleEndianData)           // PCM format
        data.append(UInt16(1).littleEndianData)           // 1 channel (mono)
        data.append(UInt32(Self.sampleRate).littleEndianData)
        data.append(UInt32(Self.sampleRate * 2).littleEndianData)  // byte rate
        data.append(UInt16(2).littleEndianData)           // block align
        data.append(UInt16(16).littleEndianData)          // bits per sample

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataByteCount).littleEndianData)

        // PCM samples — convert float [-1, 1] to int16
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

    /// Renders a gentle, resonant chord with a slow exponential decay — a low
    /// fundamental plus slightly inharmonic partials to evoke the warm,
    /// beating character of a Tibetan singing bowl. A short attack avoids any
    /// click, and an overall decay term shapes the long, soft fade.
    /// Returns an array of Float samples in [-1, 1].
    private func synthesizeChimeSamples() -> [Float] {
        let frameCount = Int(Double(Self.sampleRate) * Self.duration)
        guard frameCount > 0 else { return [] }

        // (frequency Hz, relative amplitude, per-partial decay seconds)
        let partials: [(freq: Double, amp: Double, decay: Double)] = [
            (196.00, 1.00, 2.8),  // G3 — fundamental
            (294.66, 0.55, 2.2),  // D4 — perfect fifth
            (392.00, 0.32, 1.7),  // G4 — octave
            (493.88, 0.18, 1.3),  // B4 — major third
            (587.33, 0.10, 1.0),  // D5 — fifth, a whisper on top
        ]

        let twoPi = 2.0 * Double.pi
        let sampleRateDouble = Double(Self.sampleRate)
        var samples = [Float]()
        samples.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRateDouble
            let attack = min(1.0, t / 0.015)
            let overallDecay = exp(-t / 1.8)
            var sample = 0.0
            for p in partials {
                sample += p.amp * exp(-t / p.decay) * sin(twoPi * p.freq * t)
            }
            // Keep the whole thing gentle — never louder than a soft breath.
            samples.append(Float(sample * attack * overallDecay * 0.22))
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
