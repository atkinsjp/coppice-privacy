//
//  GracePeriod.swift
//  StillHabitCalmHabitTracker
//
//  A 72-hour, no-card-required window in which every Pro feature is open.
//  StillHabitCalmHabitTracker is local-first and account-free, so the grace period is too:
//  one timestamp in UserDefaults, written the very first time the app is
//  opened and never touched again unless the user erases their data.
//

import Foundation

/// The local, credit-card-free trial that begins at first launch.
///
/// Backed by the `firstLaunchDate` key so `@AppStorage("firstLaunchDate")`
/// in a view and this helper always read the same value. `AppStorage` cannot
/// store a `Date` directly, so the timestamp is kept as a
/// `timeIntervalSince1970` `Double` — the representation `AppStorage` uses
/// for `Double` and the one `UserDefaults.double(forKey:)` reads back.
enum GracePeriod {

    /// UserDefaults key holding the first-launch timestamp.
    static let storageKey = "firstLaunchDate"

    /// How long full access lasts: 72 hours.
    static let duration: TimeInterval = 72 * 60 * 60

    // MARK: - Lifecycle

    /// Stamps "now" as the first launch if nothing has been recorded yet.
    ///
    /// Idempotent, so it is safe to call from `onAppear` of the root view on
    /// every appearance — only the first ever call writes anything.
    static func startIfNeeded() {
        guard firstLaunch == nil else { return }
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: storageKey)
        CrashDiagnostics.note("grace period started")
    }

    /// Restarts the window from now — used when the user erases all data and
    /// asks for a completely fresh start.
    static func reset() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: storageKey)
    }

    // MARK: - Reading

    /// The recorded first-launch date, or `nil` before the first stamp.
    static var firstLaunch: Date? {
        let stored = UserDefaults.standard.double(forKey: storageKey)
        // A missing key reads back as 0; a real timestamp never is.
        guard stored > 0 else { return nil }
        return Date(timeIntervalSince1970: stored)
    }

    /// The moment full access lapses, if a first launch has been recorded.
    static var expiry: Date? {
        firstLaunch.map { $0.addingTimeInterval(duration) }
    }

    /// True while the current date sits inside the 72-hour window.
    ///
    /// A first-launch stamp in the *future* (a user who moved their clock
    /// forward and back, or a restored backup) would otherwise hand out an
    /// unbounded trial, so the window is clamped at both ends.
    static var isActive: Bool {
        guard let firstLaunch else { return false }
        let elapsed = Date().timeIntervalSince(firstLaunch)
        return elapsed >= 0 && elapsed < duration
    }

    /// Seconds of full access remaining, clamped to zero.
    static var remaining: TimeInterval {
        guard let expiry else { return 0 }
        return max(0, expiry.timeIntervalSince(Date()))
    }

    // MARK: - Copy

    /// A short, calm countdown for the bottom of the settings sheet, e.g.
    /// "Premium Unlock: 2 Days Left". `nil` once the window has closed.
    static var countdownLabel: String? {
        guard isActive else { return nil }
        return "Premium Unlock: \(remainingPhrase) Left"
    }

    /// Human phrasing for the time left: days while there is more than a day,
    /// then hours, then minutes in the final stretch.
    static var remainingPhrase: String {
        let left = remaining
        if left >= 24 * 60 * 60 {
            let days = Int(ceil(left / (24 * 60 * 60)))
            return days == 1 ? "1 Day" : "\(days) Days"
        }
        if left >= 60 * 60 {
            let hours = Int(ceil(left / (60 * 60)))
            return hours == 1 ? "1 Hour" : "\(hours) Hours"
        }
        let minutes = max(1, Int(ceil(left / 60)))
        return minutes == 1 ? "1 Minute" : "\(minutes) Minutes"
    }
}
