//
//  Habit.swift
//  Stillhabit
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

@Model
final class Habit {
    var id: UUID
    var title: String
    var createdAt: Date
    var completedDates: [Date]
    var colorHex: String
    var isArchived: Bool
    /// Scheduling rule for this habit. Defaults to `.daily` so existing
    /// habits behave exactly as before the cadence feature shipped.
    var cadence: HabitCadence

    init(title: String, colorHex: String, cadence: HabitCadence = .daily) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.completedDates = []
        self.colorHex = colorHex
        self.isArchived = false
        self.cadence = cadence
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

    /// Number of completions logged so far in the current calendar week (Sunday→Saturday).
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
    func toggleCompletion(on date: Date) {
        let calendar = Calendar.current
        if let index = completedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) {
            completedDates.remove(at: index)
        } else {
            completedDates.append(date)
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
            while completedDays.contains(cursor) {
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
            while completedDays.contains(cursor) {
                streak += 1
                guard let prev = previousScheduledDay(from: cursor, weekdays: weekdays, calendar: calendar) else { break }
                cursor = prev
            }
            return streak

        case .weeklyTarget(let target):
            var cursor = Date()
            if completionsThisWeek(on: cursor) < target {
                guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
                cursor = lastWeek
            }
            var streak = 0
            while completionsThisWeek(on: cursor) >= target {
                streak += 1
                guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
                cursor = lastWeek
            }
            return streak
        }
    }

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
            guard let startWeek = calendar.dateInterval(of: .weekOfYear, for: createdAt)?.start,
                  let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
            var best = 0
            var run = 0
            var cursor = startWeek
            while cursor <= thisWeek {
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
