//
//  ReminderService.swift
//  Stillhabit
//
//  Local notification reminders for habits. Each habit may carry one
//  time-of-day reminder; the schedule follows the habit's cadence:
//    • .daily / .weeklyTarget → one repeating daily notification
//    • .specificDays([Int])   → one repeating weekly notification per day
//
//  All notifications are *local* (UNCalendarNotificationTrigger), so the app
//  needs no push entitlement, no server, and no network.
//

import Foundation
import UserNotifications

/// An immutable, Sendable snapshot of everything needed to schedule a habit's
/// reminder. Built on the main actor from a `Habit`, then handed to the
/// notification center without carrying the SwiftData model across contexts.
nonisolated struct ReminderPlan: Sendable, Equatable {
    let habitID: UUID
    let title: String
    let hour: Int
    let minute: Int
    /// Weekday indexes (1...7, Sunday...Saturday) the reminder repeats on.
    /// `nil` means every day.
    let weekdays: [Int]?
    /// The tone this reminder plays.
    let sound: ReminderSound
    /// The vibration signature this reminder plays when it surfaces in-app.
    let haptic: ReminderHaptic

    /// Builds a plan from a habit, or returns nil when the habit has no
    /// reminder, is resting, or has an unschedulable (empty) weekday set.
    init?(habit: Habit) {
        guard let minuteOfDay = habit.reminderMinuteOfDay, !habit.isArchived else { return nil }

        let clamped = max(0, min(minuteOfDay, 24 * 60 - 1))
        habitID = habit.id
        title = habit.title
        hour = clamped / 60
        minute = clamped % 60
        sound = habit.reminderSound
        haptic = habit.reminderHaptic

        switch habit.cadence {
        case .daily, .weeklyTarget:
            weekdays = nil
        case .specificDays(let days):
            let valid = days.filter { (1...7).contains($0) }.sorted()
            guard !valid.isEmpty else { return nil }
            weekdays = valid
        }
    }
}

/// Owns notification permission state and per-habit reminder scheduling.
/// A single shared instance keeps the authorization status observable across
/// every sheet that shows the reminder picker.
@Observable
final class ReminderService {
    static let shared = ReminderService()

    /// Latest known system authorization status. Refreshed on launch and
    /// whenever a sheet that can schedule reminders appears.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// True once the user has explicitly denied notifications — the picker
    /// uses this to show a quiet "open Settings" affordance instead of
    /// silently failing.
    var isDenied: Bool { authorizationStatus == .denied }

    private init() {}

    // MARK: - Permission

    /// Reads the current system authorization status into `authorizationStatus`.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Requests alert + sound permission if it hasn't been decided yet.
    /// Returns whether reminders may actually be delivered.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await refreshAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            break
        }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            print("ReminderService: authorization request failed — \(error.localizedDescription)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    // MARK: - Scheduling

    /// Cancels and (if applicable) re-creates every notification for one habit.
    func reschedule(for habit: Habit) async {
        guard habit.isAlive else { return }
        CrashDiagnostics.note("reschedule reminder")
        // The plan is built synchronously, before the first suspension point,
        // so the SwiftData model is never read after an `await`.
        await apply(ReminderPlan(habit: habit), for: habit.id)
    }

    /// Applies an already-built plan: clears whatever was scheduled for the
    /// habit and registers the new triggers. A `nil` plan just cancels.
    ///
    /// Callers that create or edit a habit should build the `ReminderPlan`
    /// while they still hold a live model and pass it here. `ReminderPlan` is
    /// an inert `Sendable` snapshot, so scheduling can safely outlive the view
    /// that started it — and can never read a habit that has meanwhile been
    /// deleted, which would raise `NSObjectInaccessibleException` and abort.
    func apply(_ plan: ReminderPlan?, for habitID: UUID) async {
        cancelReminder(habitID: habitID)
        guard let plan else { return }
        await schedule(plan)
    }

    /// Cancels every pending notification belonging to a habit. Safe to call
    /// for habits that never had a reminder.
    func cancelReminder(habitID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers(for: habitID))
    }

    /// Re-syncs all habits' reminders in one pass. Called on launch so the
    /// scheduled set always matches what's stored, even after a system reset,
    /// a restore from backup, or a timezone change.
    func syncAll(_ habits: [Habit]) async {
        let live = habits.filter { $0.isAlive }
        let plans = live.compactMap { ReminderPlan(habit: $0) }
        let identifiers = live.flatMap { Self.allIdentifiers(for: $0.id) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        guard !plans.isEmpty else { return }
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral else { return }

        for plan in plans {
            await schedule(plan)
        }
    }

    // MARK: - Private

    /// Renders every custom reminder tone to disk so the first scheduled
    /// notification never races the file write, and warms the haptic engine
    /// so a signature vibration fires without start-up latency.
    func prepareSounds() {
        ReminderSoundLibrary.shared.prepareAll()
        ReminderHapticLibrary.shared.prepare()
    }

    /// Registers the calendar triggers for one plan.
    private func schedule(_ plan: ReminderPlan) async {
        let center = UNUserNotificationCenter.current()
        let content = Self.makeContent(title: plan.title, sound: plan.sound, haptic: plan.haptic)

        var requests: [UNNotificationRequest] = []
        if let weekdays = plan.weekdays {
            for weekday in weekdays {
                var components = DateComponents()
                components.weekday = weekday
                components.hour = plan.hour
                components.minute = plan.minute
                requests.append(
                    UNNotificationRequest(
                        identifier: Self.identifier(for: plan.habitID, weekday: weekday),
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    )
                )
            }
        } else {
            var components = DateComponents()
            components.hour = plan.hour
            components.minute = plan.minute
            requests.append(
                UNNotificationRequest(
                    identifier: Self.identifier(for: plan.habitID, weekday: nil),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )
            )
        }

        for request in requests {
            do {
                try await center.add(request)
            } catch {
                print("ReminderService: failed to schedule reminder — \(error.localizedDescription)")
            }
        }
    }

    /// A quiet, non-nagging notification body in the app's voice, carrying the
    /// habit's chosen tone. A `.silent` choice leaves `sound` nil so the
    /// reminder arrives as a wordless banner. The haptic signature rides along
    /// in `userInfo`, where the presentation delegate picks it up and plays it
    /// whenever the reminder surfaces inside the app.
    private static func makeContent(
        title: String,
        sound: ReminderSound,
        haptic: ReminderHaptic
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "A quiet moment to return to this."
        content.sound = ReminderSoundLibrary.shared.notificationSound(for: sound)
        content.interruptionLevel = sound == .silent ? .passive : .active
        content.userInfo = [Self.hapticInfoKey: haptic.rawValue]
        return content
    }

    /// `userInfo` key carrying the reminder's haptic signature.
    static let hapticInfoKey = "stillhabit.reminder.haptic"

    /// Stable identifier for one habit + weekday pairing.
    private static func identifier(for habitID: UUID, weekday: Int?) -> String {
        if let weekday {
            return "habit-reminder-\(habitID.uuidString)-\(weekday)"
        }
        return "habit-reminder-\(habitID.uuidString)-daily"
    }

    /// Every identifier a habit could possibly own, used for wholesale cancel.
    private static func allIdentifiers(for habitID: UUID) -> [String] {
        var ids = [identifier(for: habitID, weekday: nil)]
        ids.append(contentsOf: (1...7).map { identifier(for: habitID, weekday: $0) })
        return ids
    }
}

/// Presents reminders as banners even while Stillhabit is open, so a reminder
/// that lands mid-session is never silently swallowed — and plays the habit's
/// haptic signature on both surfacing paths: a banner shown in the foreground,
/// and the user tapping the notification to open the app.
final class ReminderPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.playHaptic(from: notification)
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        Self.playHaptic(from: response.notification)
    }

    /// Reads the signature out of the notification payload and plays it on the
    /// main actor. Notifications without a stored signature fall back to the
    /// app's default rhythm.
    nonisolated private static func playHaptic(from notification: UNNotification) {
        let raw = notification.request.content.userInfo[ReminderService.hapticInfoKey] as? String
        Task { @MainActor in
            ReminderHapticLibrary.shared.play(rawValue: raw)
        }
    }
}
