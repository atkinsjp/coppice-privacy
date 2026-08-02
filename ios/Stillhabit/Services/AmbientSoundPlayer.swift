//
//  AmbientSoundPlayer.swift
//  Stillhabit
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
            player?.volume = volume
        }
    }

    /// Whether the selected soundscape loops endlessly (default) or plays
    /// through once and falls silent. Persisted and applied live.
    var isLoopingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoopingEnabled, forKey: Self.loopKey)
            if let player {
                player.numberOfLoops = isLoopingEnabled ? -1 : 0
                // If the single pass already ended, re-enabling looping
                // should bring the soundscape back.
                if isLoopingEnabled, current != .off, !player.isPlaying {
                    play(current)
                }
            } else if isLoopingEnabled, current != .off {
                play(current)
            }
        }
    }

    private var player: AVAudioPlayer?
    private var fadeOutTask: Task<Void, Never>?
    /// The audio session category is set exactly once per launch.
    private var hasConfiguredSession = false

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
        player?.pause()
    }

    /// Resumes the loop if a soundscape is active (app returned to foreground).
    func resume() {
        guard current != .off else { return }
        guard let player else {
            // The player was never built (or was torn down) — start fresh.
            play(current)
            return
        }
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Private

    private func play(_ sound: AmbientSound) {
        guard let name = sound.resourceName,
              let url = Bundle.main.url(forResource: name, withExtension: "mp3") else {
            print("AmbientSoundPlayer: missing resource for \(sound.rawValue)")
            return
        }

        fadeOutTask?.cancel()
        fadeOutTask = nil

        configureSessionIfNeeded()

        // Fade out any previous loop before swapping.
        if let old = player, old.isPlaying {
            old.setVolume(0, fadeDuration: Self.fadeOutDuration)
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = isLoopingEnabled ? -1 : 0
            newPlayer.volume = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            newPlayer.setVolume(volume, fadeDuration: Self.fadeInDuration)
            player = newPlayer
        } catch {
            print("AmbientSoundPlayer: failed to load \(name) — \(error.localizedDescription)")
        }
    }

    /// Sets the ambient, mix-with-others category a single time.
    ///
    /// Deliberately does **not** call `setActive(true)`: on the iOS 26
    /// simulator that call can `abort()` inside the C++ audio-session code,
    /// outside any Swift `do/catch`, taking the whole app down with SIGABRT.
    /// `AVAudioPlayer.play()` activates the session implicitly, so the loop
    /// still plays and still mixes politely with other audio.
    private func configureSessionIfNeeded() {
        guard !hasConfiguredSession else { return }
        hasConfiguredSession = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            print("AmbientSoundPlayer: audio session error — \(error.localizedDescription)")
        }
    }

    private func fadeOutAndStop() {
        guard let fading = player else { return }
        fading.setVolume(0, fadeDuration: Self.fadeOutDuration)
        player = nil

        fadeOutTask?.cancel()
        fadeOutTask = Task {
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration + 0.1))
            guard !Task.isCancelled else { return }
            fading.stop()
        }
    }
}
