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

    /// Consecutive completed days ending today (or yesterday, if today is still pending).
    var currentStreak: Int {
        let calendar = Calendar.current
        let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })
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
    }

    /// Longest run of consecutive completed days, ever.
    var bestStreak: Int {
        let calendar = Calendar.current
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
    }

    /// Total distinct days this habit was completed.
    var totalCompletions: Int {
        let calendar = Calendar.current
        return Set(completedDates.map { calendar.startOfDay(for: $0) }).count
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
