//
//  Habit.swift
//  Stillhabit
//

import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID
    var title: String
    var createdAt: Date
    var completedDates: [Date]
    var colorHex: String
    var isArchived: Bool

    init(title: String, colorHex: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.completedDates = []
        self.colorHex = colorHex
        self.isArchived = false
    }
}

extension Habit {
    /// Whether this habit was marked complete on the given calendar day.
    func isCompleted(on date: Date) -> Bool {
        let calendar = Calendar.current
        return completedDates.contains { calendar.isDate($0, inSameDayAs: date) }
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
