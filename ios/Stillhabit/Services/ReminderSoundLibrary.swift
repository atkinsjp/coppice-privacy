//
//  ReminderSoundLibrary.swift
//  Stillhabit
//
//  Distinct notification tones for habit reminders, so a Stillhabit nudge is
//  instantly recognizable and never mistaken for another app's alert.
//
//  iOS can only play a custom notification sound from a file that lives in the
//  app bundle or in the app container's `Library/Sounds` folder. Rather than
//  shipping audio files, each tone is synthesized as raw PCM (pure Swift math),
//  written once into `Library/Sounds` as a small 16-bit WAV, and referenced by
//  filename from `UNNotificationSound`. The same file backs the in-app preview
//  through AudioToolbox's `AudioServicesPlaySystemSound`, which needs no audio
//  session (see CompletionSoundService for why AVFoundation is avoided here).
//

import Foundation
import AudioToolbox
import UserNotifications

/// The tone a habit's reminder notification plays.
nonisolated enum ReminderSound: String, CaseIterable, Identifiable, Sendable {
    /// Stillhabit's signature two-note whisper — the default for every habit.
    case chime
    /// A low singing bowl with a long, settling shimmer.
    case bowl
    /// A soft hollow knock, dry and grounded.
    case wood
    /// A single water droplet, falling in pitch.
    case droplet
    /// The standard iOS notification sound.
    case systemDefault
    /// No sound at all — the reminder arrives as a silent banner.
    case silent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chime: return "Chime"
        case .bowl: return "Bowl"
        case .wood: return "Wood"
        case .droplet: return "Droplet"
        case .systemDefault: return "Default"
        case .silent: return "Silent"
        }
    }

    var symbolName: String {
        switch self {
        case .chime: return "bell"
        case .bowl: return "circle.hexagongrid"
        case .wood: return "square.stack.3d.down.right"
        case .droplet: return "drop"
        case .systemDefault: return "iphone.gen3"
        case .silent: return "bell.slash"
        }
    }

    /// The filename written into `Library/Sounds`, or nil for the two tones
    /// that need no file (system default and silent).
    var fileName: String? {
        switch self {
        case .chime: return "stillhabit-chime.wav"
        case .bowl: return "stillhabit-bowl.wav"
        case .wood: return "stillhabit-wood.wav"
        case .droplet: return "stillhabit-droplet.wav"
        case .systemDefault, .silent: return nil
        }
    }

    /// Resolves a stored raw value, falling back to the signature chime so
    /// habits created before this setting existed get Stillhabit's own tone.
    static func resolve(_ rawValue: String?) -> ReminderSound {
        guard let rawValue, let sound = ReminderSound(rawValue: rawValue) else { return .chime }
        return sound
    }
}

/// Renders the reminder tones to disk and hands out `UNNotificationSound`
/// values plus in-app previews. A single shared instance caches everything.
final class ReminderSoundLibrary {
    static let shared = ReminderSoundLibrary()

    private static let sampleRate: Int = 44100

    /// Filenames already rendered into `Library/Sounds` this session.
    private var renderedFiles: Set<String> = []
    /// Cached AudioToolbox sound IDs used for previews, keyed by tone.
    private var previewSoundIDs: [ReminderSound: SystemSoundID] = [:]

    private init() {}

    deinit {
        for id in previewSoundIDs.values where id != 0 {
            AudioServicesDisposeSystemSoundID(id)
        }
    }

    // MARK: - Notification sounds

    /// The notification sound for a tone, or nil when the reminder should be
    /// delivered silently. Renders the backing file on first use; if writing
    /// fails the call degrades to the system default rather than going silent
    /// unexpectedly.
    func notificationSound(for sound: ReminderSound) -> UNNotificationSound? {
        switch sound {
        case .silent:
            return nil
        case .systemDefault:
            return .default
        case .chime, .bowl, .wood, .droplet:
            guard let fileName = sound.fileName, ensureFile(for: sound, fileName: fileName) else {
                return .default
            }
            return UNNotificationSound(named: UNNotificationSoundName(fileName))
        }
    }

    /// Renders every custom tone up front. Called on launch so the first
    /// reminder never races the file write.
    func prepareAll() {
        for sound in ReminderSound.allCases {
            guard let fileName = sound.fileName else { continue }
            _ = ensureFile(for: sound, fileName: fileName)
        }
    }

    // MARK: - Preview

    /// Plays a tone once so the user can hear it while choosing. Respects the
    /// silent switch and degrades to nothing on any failure.
    func preview(_ sound: ReminderSound) {
        switch sound {
        case .silent:
            return
        case .systemDefault:
            // Closest stand-in for the system alert tone available to apps.
            AudioServicesPlaySystemSound(SystemSoundID(1007))
        case .chime, .bowl, .wood, .droplet:
            guard let id = previewSoundID(for: sound) else { return }
            AudioServicesPlaySystemSound(id)
        }
    }

    private func previewSoundID(for sound: ReminderSound) -> SystemSoundID? {
        if let cached = previewSoundIDs[sound], cached != 0 { return cached }
        guard let fileName = sound.fileName,
              ensureFile(for: sound, fileName: fileName),
              let url = Self.soundsDirectory()?.appendingPathComponent(fileName) else { return nil }

        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == noErr, soundID != 0 else { return nil }
        previewSoundIDs[sound] = soundID
        return soundID
    }

    // MARK: - File rendering

    /// Ensures the WAV for a tone exists in `Library/Sounds`. Returns false on
    /// any filesystem failure so callers can fall back to the system sound.
    private func ensureFile(for sound: ReminderSound, fileName: String) -> Bool {
        if renderedFiles.contains(fileName) { return true }
        guard let directory = Self.soundsDirectory() else { return false }

        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            renderedFiles.insert(fileName)
            return true
        }

        let samples = Self.samples(for: sound)
        guard !samples.isEmpty, Self.writeWAV(samples: samples, to: url) else { return false }

        renderedFiles.insert(fileName)
        return true
    }

    /// `Library/Sounds` inside the app container, created if needed. This is
    /// the only writable location iOS will load notification sounds from.
    private static func soundsDirectory() -> URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                print("ReminderSoundLibrary: could not create Sounds directory — \(error.localizedDescription)")
                return nil
            }
        }
        return directory
    }

    // MARK: - Synthesis

    /// Renders one tone's samples in [-1, 1]. Every tone is kept under two and
    /// a half seconds — well inside the 30 second limit iOS enforces — and
    /// voiced in the app's register: warm, soft-edged, never piercing.
    private static func samples(for sound: ReminderSound) -> [Float] {
        switch sound {
        case .chime:
            // E4 joined a beat later by its perfect fifth — the app's voice.
            return render(duration: 1.1, overallDecay: 0.38, gain: 0.72, partials: [
                Partial(frequency: 329.63, amplitude: 0.85, decay: 0.60, enterAt: 0),
                Partial(frequency: 493.88, amplitude: 0.55, decay: 0.50, enterAt: 0.08),
                Partial(frequency: 987.77, amplitude: 0.10, decay: 0.22, enterAt: 0.08),
            ])
        case .bowl:
            // A struck bowl: low fundamental with slightly detuned overtones
            // that beat against each other as they fade.
            return render(duration: 2.4, overallDecay: 1.05, gain: 0.68, partials: [
                Partial(frequency: 174.61, amplitude: 0.90, decay: 1.60, enterAt: 0, attack: 0.02),
                Partial(frequency: 261.63, amplitude: 0.42, decay: 1.20, enterAt: 0, attack: 0.02),
                Partial(frequency: 349.23, amplitude: 0.26, decay: 0.90, enterAt: 0, attack: 0.03),
                Partial(frequency: 352.10, amplitude: 0.20, decay: 0.90, enterAt: 0, attack: 0.03),
                Partial(frequency: 523.25, amplitude: 0.10, decay: 0.55, enterAt: 0.02),
            ])
        case .wood:
            // Two quick hollow knocks — dry, percussive, no tail.
            return render(duration: 0.42, overallDecay: 0.10, gain: 0.80, partials: [
                Partial(frequency: 392.00, amplitude: 0.70, decay: 0.05, enterAt: 0, attack: 0.002),
                Partial(frequency: 880.00, amplitude: 0.45, decay: 0.035, enterAt: 0, attack: 0.002),
                Partial(frequency: 392.00, amplitude: 0.55, decay: 0.05, enterAt: 0.16, attack: 0.002),
                Partial(frequency: 880.00, amplitude: 0.32, decay: 0.035, enterAt: 0.16, attack: 0.002),
            ])
        case .droplet:
            return renderDroplet()
        case .systemDefault, .silent:
            return []
        }
    }

    /// One sine component of a synthesized tone.
    private struct Partial {
        let frequency: Double
        let amplitude: Double
        /// Exponential decay time constant, in seconds.
        let decay: Double
        /// When this partial enters, in seconds from the start.
        let enterAt: Double
        /// Fade-in time that keeps the attack click-free.
        var attack: Double = 0.006
    }

    /// Sums a set of decaying sine partials into a normalized sample buffer.
    private static func render(
        duration: Double,
        overallDecay: Double,
        gain: Double,
        partials: [Partial]
    ) -> [Float] {
        let frameCount = Int(Double(sampleRate) * duration)
        guard frameCount > 0 else { return [] }

        let twoPi = 2.0 * Double.pi
        let rate = Double(sampleRate)
        var samples = [Float]()
        samples.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let t = Double(index) / rate
            let envelope = exp(-t / overallDecay)
            // A short fade at the very end guarantees no terminal click.
            let release = min(1.0, (duration - t) / 0.03)
            var value = 0.0
            for partial in partials where t >= partial.enterAt {
                let localT = t - partial.enterAt
                let attack = min(1.0, localT / partial.attack)
                value += partial.amplitude * attack
                    * exp(-localT / partial.decay)
                    * sin(twoPi * partial.frequency * localT)
            }
            samples.append(Float(value * envelope * release * gain))
        }
        return samples
    }

    /// A water droplet: a fast downward pitch glide with a soft resonant tail,
    /// which no additive partial set can express, so it renders on its own.
    private static func renderDroplet() -> [Float] {
        let duration = 0.55
        let frameCount = Int(Double(sampleRate) * duration)
        guard frameCount > 0 else { return [] }

        let twoPi = 2.0 * Double.pi
        let rate = Double(sampleRate)
        var samples = [Float]()
        samples.reserveCapacity(frameCount)

        var phase = 0.0
        for index in 0..<frameCount {
            let t = Double(index) / rate
            // 1150 Hz falling to ~430 Hz over the first 150 ms.
            let frequency = 430.0 + 720.0 * exp(-t / 0.05)
            phase += twoPi * frequency / rate
            let attack = min(1.0, t / 0.004)
            let envelope = exp(-t / 0.16)
            let release = min(1.0, (duration - t) / 0.03)
            // A quiet resonant ring underneath keeps it from sounding thin.
            let ring = 0.18 * exp(-t / 0.30) * sin(twoPi * 660.0 * t)
            samples.append(Float((sin(phase) * attack * envelope + ring) * release * 0.78))
        }
        return samples
    }

    // MARK: - WAV writing (no AVFoundation)

    /// Writes 16-bit mono PCM samples as a WAV file with a manual RIFF header.
    private static func writeWAV(samples: [Float], to url: URL) -> Bool {
        let dataByteCount = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        data.append(Data("RIFF".utf8))
        data.append(UInt32(4 + 24 + 8 + dataByteCount).reminderSoundLE)
        data.append(Data("WAVE".utf8))

        data.append(Data("fmt ".utf8))
        data.append(UInt32(16).reminderSoundLE)
        data.append(UInt16(1).reminderSoundLE)          // PCM
        data.append(UInt16(1).reminderSoundLE)          // mono
        data.append(UInt32(sampleRate).reminderSoundLE)
        data.append(UInt32(sampleRate * 2).reminderSoundLE)
        data.append(UInt16(2).reminderSoundLE)          // block align
        data.append(UInt16(16).reminderSoundLE)         // bit depth

        data.append(Data("data".utf8))
        data.append(UInt32(dataByteCount).reminderSoundLE)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            data.append(Int16(clamped * 32767).reminderSoundLE)
        }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("ReminderSoundLibrary: could not write tone — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }
}

// MARK: - Little-endian byte helpers

private extension UInt16 {
    var reminderSoundLE: Data {
        Data([UInt8(truncatingIfNeeded: self), UInt8(truncatingIfNeeded: self >> 8)])
    }
}

private extension UInt32 {
    var reminderSoundLE: Data {
        Data([
            UInt8(truncatingIfNeeded: self),
            UInt8(truncatingIfNeeded: self >> 8),
            UInt8(truncatingIfNeeded: self >> 16),
            UInt8(truncatingIfNeeded: self >> 24),
        ])
    }
}

private extension Int16 {
    var reminderSoundLE: Data {
        Data([UInt8(truncatingIfNeeded: self), UInt8(truncatingIfNeeded: self >> 8)])
    }
}
