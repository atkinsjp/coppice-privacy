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
    /// The exact timestamp is preserved so the app can show the completion time.
    func toggleCompletion(on date: Date) {
        let calendar = Calendar.current
        if let index = completedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) {
            completedDates.remove(at: index)
        } else {
            completedDates.append(date)
        }
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
