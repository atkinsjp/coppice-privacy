//
//  AmbientSoundPlayer.swift
//  CoppiceHabitsThatRest
//
//  A quiet, optional ambient loop (forest or rain) that plays softly
//  behind the Today view. Off by default; the choice persists.
//

import SwiftUI
import AVFoundation

/// The ambient soundscapes a user can choose from.
enum AmbientSound: String, CaseIterable {
    case off
    case forest
    case rain

    /// Bundled MP3 resource name, or nil when silent.
    var resourceName: String? {
        switch self {
        case .off: return nil
        case .forest: return "forest_ambience_loop"
        case .rain: return "gentle_rain_ambience"
        }
    }

    var icon: String {
        switch self {
        case .off: return "speaker.slash"
        case .forest: return "tree"
        case .rain: return "cloud.rain"
        }
    }

    var label: String {
        switch self {
        case .off: return "Ambient sound off"
        case .forest: return "Forest ambience"
        case .rain: return "Rain ambience"
        }
    }

    var accent: Color {
        switch self {
        case .off: return DesignSystem.Colors.textSecondary
        case .forest: return DesignSystem.Colors.sage
        case .rain: return DesignSystem.Colors.slateBlue
        }
    }

    /// The next soundscape in the cycle Off → Forest → Rain → Off.
    var next: AmbientSound {
        let all = AmbientSound.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Plays the chosen ambient loop softly and endlessly, fading in and out
/// so transitions never feel abrupt. Respects the silent switch and mixes
/// politely with any other audio (.ambient session category).
@Observable
final class AmbientSoundPlayer {

    private static let preferenceKey = "ambientSoundChoice"
    private static let volumeKey = "ambientSoundVolume"
    private static let loopKey = "ambientSoundLoops"
    private static let lastSoundKey = "ambientSoundLastNonOff"
    private static let defaultVolume: Float = 0.35
    private static let fadeInDuration: TimeInterval = 2.0
    private static let fadeOutDuration: TimeInterval = 0.8

    private(set) var current: AmbientSound

    /// Ambient loop volume (0...1), independent from the system volume.
    /// Persisted, and applied live to the active player as it changes.
    var volume: Float {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped; return }
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
            activePlayer?.volume = volume
        }
    }

    /// Whether the selected soundscape loops endlessly (default) or plays
    /// through once and falls silent. Persisted and applied live.
    var isLoopingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoopingEnabled, forKey: Self.loopKey)
            if let activePlayer {
                activePlayer.numberOfLoops = isLoopingEnabled ? -1 : 0
                // If the single pass already ended, re-enabling looping
                // should bring the soundscape back.
                if isLoopingEnabled, current != .off, !activePlayer.isPlaying {
                    play(current)
                }
            } else if isLoopingEnabled, current != .off {
                play(current)
            }
        }
    }

    /// One decoded player per soundscape, built on first use and reused for
    /// the life of the app. Rebuilding an `AVAudioPlayer` on every selection
    /// (and on every foreground return) churned the audio stack needlessly.
    private var players: [AmbientSound: AVAudioPlayer] = [:]
    /// The soundscape currently sounding, if any.
    private var activeSound: AmbientSound?
    private var fadeOutTask: Task<Void, Never>?

    /// The player backing the currently selected soundscape.
    private var activePlayer: AVAudioPlayer? {
        guard let activeSound else { return nil }
        return players[activeSound]
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? ""
        current = AmbientSound(rawValue: saved) ?? .off
        if UserDefaults.standard.object(forKey: Self.volumeKey) != nil {
            volume = min(max(UserDefaults.standard.float(forKey: Self.volumeKey), 0), 1)
        } else {
            volume = Self.defaultVolume
        }
        if UserDefaults.standard.object(forKey: Self.loopKey) != nil {
            isLoopingEnabled = UserDefaults.standard.bool(forKey: Self.loopKey)
        } else {
            isLoopingEnabled = true
        }
    }

    /// Starts the saved soundscape, if any. Call when the Today view appears.
    func startIfEnabled() {
        guard current != .off else { return }
        play(current)
    }

    /// Advances Off → Forest → Rain → Off and persists the choice.
    func cycle() {
        select(current.next)
    }

    /// Toggles between muted (`.off`) and the last-used soundscape. When
    /// muting, the current non-off choice is remembered so it can be restored
    /// on the next unmute. If no prior sound exists, forest is used.
    func toggleMuted() {
        if current == .off {
            let saved = UserDefaults.standard.string(forKey: Self.lastSoundKey) ?? ""
            let restore = AmbientSound(rawValue: saved) ?? .forest
            select(restore)
        } else {
            UserDefaults.standard.set(current.rawValue, forKey: Self.lastSoundKey)
            select(.off)
        }
    }

    /// Whether ambient sound is currently muted.
    var isMuted: Bool { current == .off }

    /// Switches to the given soundscape with a gentle crossfade.
    func select(_ sound: AmbientSound) {
        current = sound
        UserDefaults.standard.set(sound.rawValue, forKey: Self.preferenceKey)

        if sound == .off {
            fadeOutAndStop()
        } else {
            play(sound)
        }
    }

    /// Pauses playback (app moved to background).
    func pause() {
        activePlayer?.pause()
    }

    /// Resumes the loop if a soundscape is active (app returned to foreground).
    func resume() {
        guard current != .off else { return }
        guard let activePlayer else {
            // The player was never built — start fresh.
            play(current)
            return
        }
        guard !activePlayer.isPlaying else { return }
        CrashDiagnostics.note("ambient resume")
        activePlayer.play()
    }

    // MARK: - Private

    /// Returns the cached player for a soundscape, decoding it on first use.
    private func player(for sound: AmbientSound) -> AVAudioPlayer? {
        if let cached = players[sound] { return cached }
        guard let name = sound.resourceName,
              let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("AmbientSoundPlayer: missing resource for \(sound.rawValue)")
            return nil
        }
        do {
            let built = try AVAudioPlayer(contentsOf: url)
            built.volume = 0
            built.prepareToPlay()
            players[sound] = built
            return built
        } catch {
            print("AmbientSoundPlayer: failed to load \(name) — \(error.localizedDescription)")
            return nil
        }
    }

    /// Starts a soundscape, fading down whichever one was sounding before.
    ///
    /// Deliberately touches **no** `AVAudioSession` API. On the iOS 26
    /// simulator, configuring or activating the shared session can `abort()`
    /// inside C++ audio-session code, outside any Swift `do/catch`, taking the
    /// whole app down with SIGABRT. `AVAudioPlayer.play()` handles activation
    /// itself with the default category, which already respects the ringer
    /// switch — so the loop plays without ever entering that code path.
    private func play(_ sound: AmbientSound) {
        fadeOutTask?.cancel()
        fadeOutTask = nil

        // Fade out any other loop before swapping.
        for (key, other) in players where key != sound && other.isPlaying {
            other.setVolume(0, fadeDuration: Self.fadeOutDuration)
        }

        guard let target = player(for: sound) else { return }
        CrashDiagnostics.note("ambient play \(sound.rawValue)")

        target.numberOfLoops = isLoopingEnabled ? -1 : 0
        if !target.isPlaying {
            target.volume = 0
            target.play()
        }
        target.setVolume(volume, fadeDuration: Self.fadeInDuration)
        activeSound = sound

        // Park the faded-out loops once the crossfade completes.
        fadeOutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration + 0.1))
            guard !Task.isCancelled, let self else { return }
            for (key, other) in self.players where key != sound {
                other.pause()
                other.currentTime = 0
            }
        }
    }

    private func fadeOutAndStop() {
        guard let fading = activePlayer else { return }
        CrashDiagnostics.note("ambient stop")
        fading.setVolume(0, fadeDuration: Self.fadeOutDuration)
        activeSound = nil

        fadeOutTask?.cancel()
        fadeOutTask = Task {
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration + 0.1))
            guard !Task.isCancelled else { return }
            fading.pause()
            fading.currentTime = 0
        }
    }
}
