//
//  HabitModel.swift
//  StillhabitWidget
//
//  Widget-target copy of the app's SwiftData model.
//  Must stay schema-identical to ios/Stillhabit/Models/Habit.swift
//  so both binaries open the same App Group store.
//

import Foundation
import SwiftData

/// Flexible scheduling cadence for a habit. Must stay byte-identical to
/// the enum in `ios/Stillhabit/Models/Habit.swift` so both the app and the
/// widget can decode the same shared SwiftData store.
enum HabitCadence: Codable, Equatable, Hashable {
    case daily
    case specificDays([Int])
    case weeklyTarget(Int)
}

@Model
final class Habit {
    var id: UUID
    var title: String
    var createdAt: Date
    var completedDates: [Date]
    var colorHex: String
    var isArchived: Bool
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

    /// Whether the habit is scheduled for today.
    var isScheduledForToday: Bool {
        isScheduled(on: Date())
    }

    /// Number of distinct completed days in the current calendar week.
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
    /// The exact timestamp is preserved so the app can show the completion time.
    func toggleCompletion(on date: Date) {
        let calendar = Calendar.current
        if let index = completedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) {
            completedDates.remove(at: index)
        } else {
            completedDates.append(date)
        }
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
