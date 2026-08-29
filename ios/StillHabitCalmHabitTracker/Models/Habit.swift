//
//  Habit.swift
//  StillHabitCalmHabitTracker
//

import Foundation
import SwiftData

/// Flexible scheduling cadence for a habit.
/// - `.daily`: scheduled every day
/// - `.specificDays([Int])`: scheduled on the given weekday indexes (1...7, Sunday...Saturday)
/// - `.weeklyTarget(Int)`: a soft goal of N completions per week (1...6)
enum HabitCadence: Codable, Equatable, Hashable {
    case daily
    case specificDays([Int])
    case weeklyTarget(Int)

    /// Stable string representation used only for debugging / logging.
    var debugDescription: String {
        switch self {
        case .daily: return "daily"
        case .specificDays(let days): return "specificDays(\(days))"
        case .weeklyTarget(let target): return "weeklyTarget(\(target))"
        }
    }
}

/// How a habit is measured and logged.
/// - `.checkIn`: standard Yes/No -- one tap completes the day
/// - `.numeric(target:unit:)`: a measurable daily target, e.g. 64 oz of water.
///   Quick-add pills increment the day's accumulated value; when the target
///   is reached the day is marked complete.
/// - `.duration(targetMinutes:)`: a focus timer, e.g. 20 minutes of reading.
///   When the elapsed seconds reach the target, the day is marked complete.
enum HabitType: Codable, Equatable, Hashable {
    case checkIn
    case numeric(target: Double, unit: String)
    case duration(targetMinutes: Int)

    /// Stable string representation used only for debugging / logging.
    var debugDescription: String {
        switch self {
        case .checkIn: return "checkIn"
        case .numeric(let target, let unit): return "numeric(\(target) \(unit))"
        case .duration(let minutes): return "duration(\(minutes)m)"
        }
    }
}

/// A single granular progress entry for `.numeric` and `.duration` habits.
/// `loggedValue` is a count for numeric habits and elapsed seconds for
/// duration habits. `checkIn` habits never produce logs -- they only flip
/// `completedDates`. Stored alongside `completedDates` so the canonical
/// "done today" flag and streak logic stay untouched.
struct HabitLog: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var date: Date
    var loggedValue: Double

    init(id: UUID = UUID(), date: Date = Date(), loggedValue: Double) {
        self.id = id
        self.date = date
        self.loggedValue = loggedValue
    }
}

@Model
final class Habit {
    // All stored properties have inline defaults -- CloudKit's SwiftData
    // integration requires this so the schema can be initialized without
    // a Swift init call during sync.
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var completedDates: [Date] = []
    var colorHex: String = ""
    var isArchived: Bool = false
    /// JSON-encoded `HabitCadence`. CloudKit does not support Codable enums
    /// with associated values as attribute types, so the cadence is serialized
    /// to `Data` and exposed through the computed `cadence` property.
    var cadenceData: Data? = nil
    /// JSON-encoded `HabitType`. Same CloudKit constraint as `cadenceData`.
    var typeData: Data? = nil
    /// JSON-encoded `[HabitLog]`. CloudKit does not support arrays of custom
    /// Codable structs as attribute types.
    var logsData: Data? = nil
    /// Wall-clock anchor for an actively running `.duration` focus timer.
    /// Non-nil while the timer is running; set to `nil` on pause or completion.
    /// Persisted so elapsed time stays accurate when the app is backgrounded,
    /// the phone is locked, or the app is killed and relaunched -- progress is
    /// always `Date().timeIntervalSince(timerStart)` plus accumulated `logs`.
    var timerStart: Date? = nil
    /// Optional intentionality anchor -- a short, user-authored reminder of
    /// *why* this habit matters, revealed as a reflective moment on the card
    /// right before the user logs progress. nil keeps the resting card clean.
    var whyString: String? = nil
    /// Manual ordering for the Today list. Lower values appear first. New
    /// habits are appended after all existing non-archived habits. Only
    /// consulted when the sort mode is `.manual`; other sort modes ignore it.
    var order: Int = 0
    /// Minutes since local midnight (0...1439) for this habit's daily
    /// notification reminder, or nil when no reminder is set. Stored as a
    /// wall-clock offset rather than a `Date` so the reminder always fires at
    /// the same local time regardless of timezone travel or daylight saving.
    var reminderMinuteOfDay: Int? = nil
    /// Raw value of the `ReminderSound` this habit's notification plays. nil
    /// resolves to the app's signature chime, so habits created before this
    /// setting existed still sound like StillHabitCalmHabitTracker rather than a generic alert.
    var reminderSoundRaw: String? = nil
    /// Raw value of the `ReminderHaptic` signature this habit's reminder plays.
    /// nil resolves to the breath rhythm, so a habit can be recognized by
    /// feel alone even with the ringer off.
    var reminderHapticRaw: String? = nil

    // MARK: - CloudKit-compatible typed accessors

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    /// Scheduling rule for this habit, encoded as `cadenceData` for CloudKit.
    var cadence: HabitCadence {
        get {
            guard let data = cadenceData,
                  let decoded = try? Self.jsonDecoder.decode(HabitCadence.self, from: data) else { return .daily }
            return decoded
        }
        set { cadenceData = try? Self.jsonEncoder.encode(newValue) }
    }

    /// How this habit is measured and logged, encoded as `typeData` for CloudKit.
    var type: HabitType {
        get {
            guard let data = typeData,
                  let decoded = try? Self.jsonDecoder.decode(HabitType.self, from: data) else { return .checkIn }
            return decoded
        }
        set { typeData = try? Self.jsonEncoder.encode(newValue) }
    }

    /// Granular progress entries for `.numeric` and `.duration` habits,
    /// encoded as `logsData` for CloudKit.
    var logs: [HabitLog] {
        get {
            guard let data = logsData,
                  let decoded = try? Self.jsonDecoder.decode([HabitLog].self, from: data) else { return [] }
            return decoded
        }
        set { logsData = try? Self.jsonEncoder.encode(newValue) }
    }

    init(
        title: String,
        colorHex: String,
        cadence: HabitCadence = .daily,
        type: HabitType = .checkIn,
        whyString: String? = nil,
        order: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.completedDates = []
        self.colorHex = colorHex
        self.isArchived = false
        self.cadence = cadence
        self.type = type
        self.logsData = nil
        self.timerStart = nil
        self.whyString = whyString?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? whyString?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        self.order = order
    }
}

extension Habit {
    /// Whether this habit was marked complete on the given calendar day.
    func isCompleted(on date: Date) -> Bool {
        let calendar = Calendar.current
        return completedDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    /// Whether the given date is a scheduled day for this habit, per its cadence.
    /// `.daily` is always scheduled; `.specificDays` checks the weekday index;
    /// `.weeklyTarget` is always considered scheduled (the user may complete it
    /// on any day until the weekly goal is met).
    func isScheduled(on date: Date) -> Bool {
        let calendar = Calendar.current
        switch cadence {
        case .daily:
            return true
        case .specificDays(let weekdays):
            let weekdayIndex = calendar.component(.weekday, from: date)
            return weekdays.contains(weekdayIndex)
        case .weeklyTarget:
            return true
        }
    }

    /// Convenience for whether the habit is scheduled for today.
    var isScheduledForToday: Bool {
        isScheduled(on: Date())
    }

    /// The name of the next weekday this habit runs on, when it is not
    /// scheduled today ("Tuesday"). nil when the habit runs today, or its
    /// cadence is daily / weekly-target (always scheduled).
    var nextScheduledWeekdayName: String? {
        guard !isScheduledForToday else { return nil }
        guard case .specificDays(let weekdays) = cadence else { return nil }
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())
        let sorted = weekdays.sorted()
        guard let next = sorted.first(where: { $0 > today }) ?? sorted.first else { return nil }
        return calendar.weekdaySymbols[next - 1]
    }

    /// Whether this habit carries a non-empty intentionality anchor (the
    /// "why"). Cards use this to decide whether to reserve space for the
    /// reflective reveal at all.
    var hasWhyAnchor: Bool {
        guard let whyString, !whyString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    /// The trimmed intentionality anchor, or nil if none.
    var whyAnchorText: String? {
        guard hasWhyAnchor else { return nil }
        return whyString?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Number of completions logged so far in the current calendar week (Sunday to Saturday).
    func completionsThisWeek(on referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return 0 }
        return completedDates.reduce(into: Set<Date>()) { result, completion in
            if weekInterval.contains(completion) {
                result.insert(calendar.startOfDay(for: completion))
            }
        }.count
    }

    /// For `.weeklyTarget` habits: the target count (0 for other cadences).
    var weeklyTarget: Int {
        if case .weeklyTarget(let target) = cadence { return target }
        return 0
    }

    /// For `.weeklyTarget` habits: whether this week's target has been met.
    var weeklyTargetMet: Bool {
        guard case .weeklyTarget = cadence else { return false }
        return completionsThisWeek() >= weeklyTarget
    }

    /// Adds or removes a completion entry for the given calendar day.
    /// The exact timestamp is preserved so the completion time can be shown later.
    /// For `.numeric` and `.duration` habits, removing today's completion also
    /// discards that day's granular logs so progress resets cleanly.
    func toggleCompletion(on date: Date) {
        let calendar = Calendar.current
        if let index = completedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) {
            completedDates.remove(at: index)
            if calendar.isDateInToday(date) {
                var updatedLogs = logs
                updatedLogs.removeAll { calendar.isDate($0.date, inSameDayAs: date) }
                logs = updatedLogs
            }
        } else {
            completedDates.append(date)
        }
    }

    // MARK: - Typed logging

    /// The numeric target for `.numeric` habits (0 otherwise).
    var numericTarget: Double {
        if case .numeric(let target, _) = type { return target }
        return 0
    }

    /// The unit label for `.numeric` habits (empty otherwise).
    var numericUnit: String {
        if case .numeric(_, let unit) = type { return unit }
        return ""
    }

    /// The duration target in minutes for `.duration` habits (0 otherwise).
    var durationTargetMinutes: Int {
        if case .duration(let minutes) = type { return minutes }
        return 0
    }

    /// The duration target in seconds for `.duration` habits (0 otherwise).
    var durationTargetSeconds: Double {
        Double(durationTargetMinutes) * 60
    }

    /// Total logged value for the given calendar day. For `.numeric` habits
    /// this is the accumulated count; for `.duration` habits, elapsed seconds.
    func loggedValue(on date: Date) -> Double {
        let calendar = Calendar.current
        return logs
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.loggedValue }
    }

    /// Today's accumulated value (count or elapsed seconds).
    var loggedToday: Double { loggedValue(on: Date()) }

    /// Completion progress for the given calendar day, clamped to 0...1.
    /// Used by the 90-day heatmap to shade each cell by exact partial progress:
    /// 0 = faint background, 0.01-0.99 = semi-transparent accent proportional
    /// to progress, 1.0+ = solid accent. For `.checkIn` habits this is binary;
    /// for `.numeric`/`.duration` it reflects `loggedValue / target`. A day that
    /// is in `completedDates` always reads as fully complete (1.0) so the
    /// canonical completion flag stays authoritative.
    func progress(on date: Date) -> Double {
        if isCompleted(on: date) { return 1 }
        switch type {
        case .checkIn:
            return 0
        case .numeric(let target, _):
            guard target > 0 else { return 0 }
            return min(loggedValue(on: date) / target, 1)
        case .duration(let minutes):
            guard minutes > 0 else { return 0 }
            return min(loggedValue(on: date) / (Double(minutes) * 60), 1)
        }
    }

    /// Progress toward today's target, clamped to 0...1. For `.checkIn` habits
    /// this is simply 1 when complete, 0 otherwise.
    var todayProgress: Double {
        switch type {
        case .checkIn:
            return isCompleted(on: Date()) ? 1 : 0
        case .numeric(let target, _):
            guard target > 0 else { return 0 }
            return min(loggedToday / target, 1)
        case .duration(let minutes):
            guard minutes > 0 else { return 0 }
            return min(loggedToday / (Double(minutes) * 60), 1)
        }
    }

    /// Appends a granular log entry for today and, if the target is now met,
    /// marks today complete (preserving the exact completion timestamp so
    /// streaks and the heatmap keep working unchanged). Does nothing for
    /// `.checkIn` habits -- those use `toggleCompletion` directly.
    func logProgress(_ value: Double, on date: Date = Date()) {
        guard value != 0 else { return }
        switch type {
        case .checkIn:
            return
        case .numeric, .duration:
            var updatedLogs = logs
            updatedLogs.append(HabitLog(date: date, loggedValue: value))
            logs = updatedLogs
            if !isCompleted(on: date), todayProgress >= 1 {
                completedDates.append(date)
            }
        }
    }

    /// A short, human-readable summary of the habit's measurement, e.g.
    /// "64 oz/day", "20 min/day", or "Yes/No". Used in the detail view.
    var typeSummary: String {
        switch type {
        case .checkIn: return "Yes / No"
        case .numeric(let target, let unit):
            return ValueFormatter.wholeOrDecimal(target) + " " + unit + "/day"
        case .duration(let minutes):
            return "\(minutes) min/day"
        }
    }

    /// Today's progress as a display string, e.g. "32 / 64 oz" or "12:30 / 20:00".
    var todayProgressLabel: String {
        switch type {
        case .checkIn:
            return isCompleted(on: Date()) ? "Done" : "Not done"
        case .numeric(let target, let unit):
            return ValueFormatter.wholeOrDecimal(loggedToday)
                + " / " + ValueFormatter.wholeOrDecimal(target) + " " + unit
        case .duration(let minutes):
            let elapsed = Int(loggedToday)
            return ValueFormatter.clockString(seconds: elapsed)
                + " / " + ValueFormatter.clockString(seconds: minutes * 60)
        }
    }

    /// The most recent completion timestamp, if any.
    var lastCompletion: Date? {
        completedDates.max()
    }

    /// The stored completion timestamp for the given calendar day, if completed.
    func completionTimestamp(on date: Date) -> Date? {
        let calendar = Calendar.current
        return completedDates.first { calendar.isDate($0, inSameDayAs: date) }
    }

    /// Consecutive completed scheduled days ending today (or the most recent
    /// scheduled day, if today is still pending). Schedule-aware: for
    /// `.specificDays`, unscheduled days are simply skipped rather than
    /// breaking the streak; for `.weeklyTarget`, a "streak" is consecutive
    /// weeks in which the target was met. `completedDates` is never modified
    /// when cadence changes, so all historical progress is preserved and
    /// streaks recompute against the new schedule going forward.
    var currentStreak: Int {
        let calendar = Calendar.current
        let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })

        switch cadence {
        case .daily:
            var cursor = calendar.startOfDay(for: Date())
            if !completedDays.contains(cursor) {
                guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
                cursor = yesterday
            }
            var streak = 0
            // A streak can never be longer than the number of days actually
            // recorded, so the walk is bounded by the data rather than trusting
            // the loop condition to fail. See `Self.streakIterationLimit`.
            while streak < completedDays.count, completedDays.contains(cursor) {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            }
            return streak

        case .specificDays(let weekdays):
            guard !weekdays.isEmpty else { return 0 }
            var cursor = calendar.startOfDay(for: Date())
            if !weekdays.contains(calendar.component(.weekday, from: cursor)) {
                guard let prev = previousScheduledDay(from: cursor, weekdays: weekdays, calendar: calendar) else { return 0 }
                cursor = prev
            }
            if !completedDays.contains(cursor) {
                guard let prev = previousScheduledDay(from: cursor, weekdays: weekdays, calendar: calendar) else { return 0 }
                cursor = prev
            }
            var streak = 0
            while streak < completedDays.count, completedDays.contains(cursor) {
                streak += 1
                guard let prev = previousScheduledDay(from: cursor, weekdays: weekdays, calendar: calendar) else { break }
                cursor = prev
            }
            return streak

        case .weeklyTarget(let target):
            // A non-positive target makes `completionsThisWeek >= target`
            // permanently true, which would walk backwards through the calendar
            // forever and wedge the main thread. The UI clamps the goal to
            // 1...6, but stored data is not trusted to have done so.
            guard target > 0 else { return 0 }
            var cursor = Date()
            if completionsThisWeek(on: cursor) < target {
                guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
                cursor = lastWeek
            }
            var streak = 0
            while streak < Self.streakIterationLimit, completionsThisWeek(on: cursor) >= target {
                streak += 1
                guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
                cursor = lastWeek
            }
            return streak
        }
    }

    /// Hard ceiling on any backwards calendar walk. Ten years of weeks is far
    /// beyond any real streak; its only job is to guarantee termination if the
    /// stored data is ever inconsistent, because these loops run on the main
    /// thread during view rendering and a hang there kills the app.
    private static let streakIterationLimit = 520

    /// Longest run of consecutive completed scheduled days, ever. Schedule-aware:
    /// for `.specificDays`, runs are counted across scheduled days only; for
    /// `.weeklyTarget`, runs are consecutive target-metting weeks.
    var bestStreak: Int {
        let calendar = Calendar.current

        switch cadence {
        case .daily:
            let days = Set(completedDates.map { calendar.startOfDay(for: $0) }).sorted()
            var best = 0
            var run = 0
            var previous: Date?
            for day in days {
                if let previous,
                   let expected = calendar.date(byAdding: .day, value: 1, to: previous),
                   calendar.isDate(expected, inSameDayAs: day) {
                    run += 1
                } else {
                    run = 1
                }
                best = max(best, run)
                previous = day
            }
            return best

        case .specificDays(let weekdays):
            guard !weekdays.isEmpty else { return 0 }
            let completedScheduled = Set(completedDates.map { calendar.startOfDay(for: $0) })
                .filter { weekdays.contains(calendar.component(.weekday, from: $0)) }
                .sorted()
            var best = 0
            var run = 0
            var previous: Date?
            for day in completedScheduled {
                if let previous,
                   let expected = nextScheduledDay(from: previous, weekdays: weekdays, calendar: calendar),
                   calendar.isDate(expected, inSameDayAs: day) {
                    run += 1
                } else {
                    run = 1
                }
                best = max(best, run)
                previous = day
            }
            return best

        case .weeklyTarget(let target):
            guard target > 0,
                  let startWeek = calendar.dateInterval(of: .weekOfYear, for: createdAt)?.start,
                  let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
            var best = 0
            var run = 0
            var cursor = startWeek
            var iterations = 0
            while cursor <= thisWeek, iterations < Self.streakIterationLimit {
                iterations += 1
                if completionsThisWeek(on: cursor) >= target {
                    run += 1
                    best = max(best, run)
                } else {
                    run = 0
                }
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
                cursor = next
            }
            return best
        }
    }

    /// Total distinct days this habit was completed.
    var totalCompletions: Int {
        let calendar = Calendar.current
        return Set(completedDates.map { calendar.startOfDay(for: $0) }).count
    }

    /// A short, human-readable summary of the cadence, e.g. "Every day",
    /// "Mon, Wed, Fri", or "3 times a week". Used in the detail view.
    var cadenceSummary: String {
        switch cadence {
        case .daily: return "Every day"
        case .specificDays(let weekdays):
            return Habit.weekdaySummary(weekdays)
        case .weeklyTarget(let target):
            return "\(target) times a week"
        }
    }

    // MARK: - Reminder

    /// Whether a time-of-day reminder is set for this habit.
    var hasReminder: Bool { reminderMinuteOfDay != nil }

    /// The tone this habit's reminder plays, resolved from storage.
    var reminderSound: ReminderSound {
        get { ReminderSound.resolve(reminderSoundRaw) }
        set { reminderSoundRaw = newValue.rawValue }
    }

    /// The vibration signature this habit's reminder plays, resolved from storage.
    var reminderHaptic: ReminderHaptic {
        get { ReminderHaptic.resolve(reminderHapticRaw) }
        set { reminderHapticRaw = newValue.rawValue }
    }

    /// The reminder time projected onto today's date, suitable for binding to
    /// a `DatePicker`. Falls back to 8:00 AM when no reminder is set.
    var reminderTimeToday: Date {
        Habit.date(fromMinuteOfDay: reminderMinuteOfDay ?? 8 * 60)
    }

    /// Localized short time string for the reminder, e.g. "7:30 AM", or nil.
    var reminderSummary: String? {
        guard reminderMinuteOfDay != nil else { return nil }
        return reminderTimeToday.formatted(date: .omitted, time: .shortened)
    }

    /// Converts a minutes-since-midnight offset into a `Date` on today's calendar day.
    static func date(fromMinuteOfDay minutes: Int) -> Date {
        let calendar = Calendar.current
        let clamped = max(0, min(minutes, 24 * 60 - 1))
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? start
    }

    /// Extracts minutes-since-midnight from a `Date`'s local hour and minute.
    static func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Comma-separated short weekday names for the given weekday indexes (1...7).
    static func weekdaySummary(_ weekdays: [Int]) -> String {
        guard !weekdays.isEmpty else { return "No days" }
        let symbols = Calendar.current.shortWeekdaySymbols
        let names = weekdays.sorted().compactMap { index -> String? in
            guard index >= 1, index <= symbols.count else { return nil }
            return symbols[index - 1]
        }
        return names.joined(separator: ", ")
    }

    /// The next scheduled day strictly after the given day, or nil.
    private func nextScheduledDay(from date: Date, weekdays: [Int], calendar: Calendar) -> Date? {
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            if weekdays.contains(calendar.component(.weekday, from: next)) { return next }
            cursor = next
        }
        return nil
    }

    /// The previous scheduled day strictly before the given day, or nil.
    private func previousScheduledDay(from date: Date, weekdays: [Int], calendar: Calendar) -> Date? {
        var cursor = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            if weekdays.contains(calendar.component(.weekday, from: prev)) { return prev }
            cursor = prev
        }
        return nil
    }

    // MARK: - Reflective analytics

    /// The trailing `lastNDays` calendar days, clipped so the window never
    /// begins before the habit existed. Oldest first, today last.
    private func recentWindow(lastNDays: Int) -> [Date] {
        guard lastNDays > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let rawStart = calendar.date(byAdding: .day, value: -(lastNDays - 1), to: today) else { return [] }
        let start = max(rawStart, calendar.startOfDay(for: createdAt))
        guard start <= today else { return [] }

        var days: [Date] = []
        var cursor = start
        while cursor <= today {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Share of *scheduled* days completed over the trailing window, as a
    /// fraction from 0.0 to 1.0.
    ///
    /// The denominator respects the habit's cadence rather than the raw day
    /// count, so a Mon/Wed/Fri habit isn't quietly punished for its rest days:
    /// - `.daily` -- every day in the window counts.
    /// - `.specificDays` -- only matching weekdays count.
    /// - `.weeklyTarget(n)` -- the expectation is `n` completions per week,
    ///   pro-rated across the window.
    ///
    /// The window is clipped to the habit's creation date, so a habit that is
    /// three days old is measured against three days, not thirty. Returns 0
    /// when nothing was ever scheduled.
    func completionRatePercentage(for lastNDays: Int = 30) -> Double {
        let calendar = Calendar.current
        let days = recentWindow(lastNDays: lastNDays)
        guard !days.isEmpty else { return 0 }

        let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })

        switch cadence {
        case .daily, .specificDays:
            let scheduled = days.filter { isScheduled(on: $0) }
            guard !scheduled.isEmpty else { return 0 }
            let done = scheduled.filter { completedDays.contains($0) }.count
            return min(Double(done) / Double(scheduled.count), 1)

        case .weeklyTarget(let target):
            let expected = Double(max(target, 1)) * (Double(days.count) / 7)
            guard expected > 0 else { return 0 }
            let done = days.filter { completedDays.contains($0) }.count
            return min(Double(done) / expected, 1)
        }
    }

    /// The part of the day this habit is most often completed in, inferred
    /// from the hour of each completion timestamp in the trailing window.
    /// Returns `nil` until there are at least `minimumSamples` completions --
    /// an observation, never a guess.
    func timeOfDayPattern(for lastNDays: Int = 30, minimumSamples: Int = 3) -> TimeOfDayPattern? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard lastNDays > 0,
              let windowStart = calendar.date(byAdding: .day, value: -(lastNDays - 1), to: today) else { return nil }

        let recent = completedDates.filter { $0 >= windowStart }
        guard recent.count >= minimumSamples else { return nil }

        var tally: [TimeOfDayPattern: Int] = [:]
        for completion in recent {
            let hour = calendar.component(.hour, from: completion)
            tally[TimeOfDayPattern(hour: hour), default: 0] += 1
        }

        // Ties resolve by the natural order of the day so the result is stable.
        return tally
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.order < rhs.key.order : lhs.value > rhs.value
            }
            .first?
            .key
    }

    /// Human-readable name of the part of day this habit gravitates toward
    /// ("Morning", "Afternoon", "Evening", "Night"), or nil without enough data.
    func mostCommonTimeOfDay(for lastNDays: Int = 30) -> String? {
        timeOfDayPattern(for: lastNDays)?.displayName
    }

    /// Completion flags for the trailing `days` calendar days, oldest first (today last).
    func completionTrail(days: Int) -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return completedDates.contains { calendar.isDate($0, inSameDayAs: day) }
        }
    }
}

/// Quiet number formatting helpers for typed habit values.
enum ValueFormatter {
    /// Prints a Double as an integer when whole, otherwise with up to one
    /// decimal place and trailing zeros stripped (e.g. 64 -> "64", 0.5 -> "0.5").
    static func wholeOrDecimal(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        let formatted = String(format: "%.1f", value)
        return formatted.hasSuffix(".0") ? String(format: "%.0f", value) : formatted
    }

    /// Formats an elapsed-seconds value as `m:ss` (e.g. 1198 -> "19:58").
    /// Hours are not promoted -- focus targets are 1-120 minutes.
    static func clockString(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let secs = clamped % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
