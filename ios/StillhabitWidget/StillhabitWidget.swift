//
//  StillhabitWidget.swift
//  StillhabitWidget
//
//  Small: today's completion ring with a one-tap log button.
//  Medium: up to 3 habits with a 7-day dot trail; today's dot is interactive.
//

import WidgetKit
import SwiftUI

// MARK: - Entry

nonisolated struct HabitSnapshot: Identifiable {
    let id: UUID
    let title: String
    let colorHex: String
    let isDoneToday: Bool
    /// Trailing 7 days, oldest first (today last).
    let trail: [Bool]
}

nonisolated struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
    let totalCount: Int
    let completedCount: Int

    var topUncompleted: HabitSnapshot? {
        habits.first { !$0.isDoneToday }
    }

    static let placeholder = HabitEntry(
        date: Date(),
        habits: [
            HabitSnapshot(id: UUID(), title: "Morning stretch", colorHex: "8A9A86", isDoneToday: true, trail: [true, false, true, true, true, false, true]),
            HabitSnapshot(id: UUID(), title: "Read ten pages", colorHex: "C8826D", isDoneToday: false, trail: [false, true, true, false, true, true, false]),
            HabitSnapshot(id: UUID(), title: "Evening walk", colorHex: "7A8B99", isDoneToday: false, trail: [true, true, false, true, false, true, false]),
        ],
        totalCount: 3,
        completedCount: 1
    )

    @MainActor
    static func load() -> HabitEntry {
        let habits = WidgetStore.fetchActiveHabits()
        let today = Date()
        let snapshots = habits.map { habit in
            HabitSnapshot(
                id: habit.id,
                title: habit.title,
                colorHex: habit.colorHex,
                isDoneToday: habit.isCompleted(on: today),
                trail: habit.completionTrail(days: 7)
            )
        }
        return HabitEntry(
            date: today,
            habits: snapshots,
            totalCount: snapshots.count,
            completedCount: snapshots.filter { $0.isDoneToday }.count
        )
    }
}

// MARK: - Provider

nonisolated struct HabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in
            completion(HabitEntry.load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        Task { @MainActor in
            let entry = HabitEntry.load()
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
        }
    }
}

// MARK: - Root view

struct StillhabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallHabitsView(entry: entry)
            default:
                MediumHabitsView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            WidgetDesign.background
        }
    }
}

// MARK: - Widget

struct StillhabitWidget: Widget {
    let kind: String = "StillhabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitProvider()) { entry in
            StillhabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's habits")
        .description("Log habits quietly, right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
