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

/// How a habit is measured and logged. Must stay byte-identical to the enum
/// in the app target so the shared store decodes.
enum HabitType: Codable, Equatable, Hashable {
    case checkIn
    case numeric(target: Double, unit: String)
    case duration(targetMinutes: Int)
}

/// A single granular progress entry for `.numeric` and `.duration` habits.
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
    // Inline defaults required by CloudKit's SwiftData integration.
    // Must stay schema-identical with the app target.
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var completedDates: [Date] = []
    var colorHex: String = ""
    var isArchived: Bool = false
    /// JSON-encoded `HabitCadence`. Must stay schema-identical with the app target.
    var cadenceData: Data? = nil
    /// JSON-encoded `HabitType`. Must stay schema-identical with the app target.
    var typeData: Data? = nil
    /// JSON-encoded `[HabitLog]`. Must stay schema-identical with the app target.
    var logsData: Data? = nil
    /// Wall-clock anchor for an actively running `.duration` focus timer.
    var timerStart: Date? = nil
    /// Optional intentionality anchor.
    var whyString: String? = nil
    /// Manual ordering for the Today list. Lower values appear first.
    var order: Int = 0
    /// Minutes since local midnight for the habit's reminder, or nil.
    var reminderMinuteOfDay: Int? = nil
    /// Raw value of the reminder tone.
    var reminderSoundRaw: String? = nil
    /// Raw value of the reminder haptic signature.
    var reminderHapticRaw: String? = nil

    // MARK: - CloudKit-compatible typed accessors

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    var cadence: HabitCadence {
        get {
            guard let data = cadenceData,
                  let decoded = try? Self.jsonDecoder.decode(HabitCadence.self, from: data) else { return .daily }
            return decoded
        }
        set { cadenceData = try? Self.jsonEncoder.encode(newValue) }
    }

    var type: HabitType {
        get {
            guard let data = typeData,
                  let decoded = try? Self.jsonDecoder.decode(HabitType.self, from: data) else { return .checkIn }
            return decoded
        }
        set { typeData = try? Self.jsonEncoder.encode(newValue) }
    }

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
        self.whyString = whyString
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

    /// Schedule-aware streak matching the app's `Habit.currentStreak`.
    /// `completedDates` is never modified when cadence changes, so streaks
    /// recompute against the new schedule going forward.
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
            // Bounded by the data itself: a streak can never be longer than the
            // number of days actually recorded. The widget runs in a separate
            // process holding the shared store open, so a runaway loop here
            // would wedge that process while the app waits on the same store.
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
            // A non-positive target makes the comparison permanently true,
            // which would walk backwards through the calendar forever.
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

    /// Hard ceiling on any backwards calendar walk. Matches the app target.
    private static let streakIterationLimit = 520

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
