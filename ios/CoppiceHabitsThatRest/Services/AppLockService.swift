//
//  AppLockService.swift
//  CoppiceHabitsThatRest
//
//  Optional biometric gate for the whole app. When enabled, leaving the
//  app hides every habit behind a quiet lock screen until the user proves
//  their identity with Face ID (with device-passcode fallback). Habits and
//  data are never affected by the lock — it is purely a privacy curtain,
//  mirroring the design decision that Stillhabit keeps no accounts.
//

import Foundation
import LocalAuthentication

/// Owns the Face ID lock lifecycle: enable/disable from Settings, engage on
/// backgrounding, verify on return.
///
/// **Fail-open policy:** if the device cannot perform any authentication at
/// all (no biometrics *and* no device passcode — typical of simulators),
/// engaging the lock is refused at enable-time and an in-flight unlock
/// silently releases rather than permanently locking the owner out of their
/// own journal.
@Observable
final class AppLockService {

    /// UserDefaults key backing `isLockEnabled`.
    static let storageKey = "stillhabit.appLockEnabled"

    private let defaults: UserDefaults

    /// True while app content must be hidden behind the lock screen.
    /// Read by the root overlay; driven only by `lockIfNeeded()` /
    /// `authenticate()`.
    private(set) var isLocked = false

    /// Guards against stacking system authentication dialogs when the
    /// auto-prompt and a manual tap race each other.
    private var isAuthenticating = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the lock is switched on in Settings.
    var isLockEnabled: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    // MARK: - Lifecycle

    /// Engages the lock as the app leaves the foreground. A no-op when the
    /// feature is off or already engaged.
    func lockIfNeeded() {
        guard isLockEnabled, !isLocked else { return }
        isLocked = true
    }

    /// Runs the system authentication flow. On success the content returns;
    /// a failure or cancel simply keeps the lock screen up for another try.
    func authenticate() async {
        guard isLocked, !isAuthenticating else { return }
        // Device lost its auth methods mid-session (passcode removed etc.)
        // → release rather than strand the user outside their own data.
        guard canAuthenticate() else {
            isLocked = false
            CrashDiagnostics.note("applock auth unavailable, released")
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let succeeded = await performEvaluation(reason: "Unlock your habits")
        if succeeded {
            isLocked = false
        }
    }

    /// Enables or disables the lock from Settings.
    ///
    /// Enabling verifies identity once immediately, both as a confirmation
    /// ritual and so nobody can flick the lock onto someone else's unlocked
    /// phone as a prank. Returns whether the new state took effect; a `false`
    /// means the device could not authenticate (no Face ID / passcode).
    @discardableResult
    func setLockEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isLockEnabled else { return true }

        guard enabled else {
            defaults.set(false, forKey: Self.storageKey)
            return true
        }

        guard canAuthenticate() else { return false }

        isAuthenticating = true
        defer { isAuthenticating = false }
        let confirmed = await performEvaluation(reason: "Confirm to require Face ID")
        guard confirmed else { return false }

        defaults.set(true, forKey: Self.storageKey)
        return true
    }

    // MARK: - Biometrics plumbing

    /// Whether the device offers *any* acceptable authentication path.
    /// `.deviceOwnerAuthentication` covers Face ID / Touch ID and falls back
    /// to the device passcode automatically.
    private func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// One round of the system authentication dialog.
    private func performEvaluation(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
