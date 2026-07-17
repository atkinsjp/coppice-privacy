//
//  MediumHabitsView.swift
//  StillhabitWidget
//
//  Up to 3 habit rows: title on the left, a 7-day dot trail on the right.
//  Today's dot is a fixed-size interactive button — no layout shift on toggle.
//

import SwiftUI
import WidgetKit

struct MediumHabitsView: View {
    let entry: HabitEntry

    private var rows: [HabitSnapshot] {
        Array(entry.habits.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if rows.isEmpty {
                emptyState
            } else {
                Spacer(minLength: 6)
                VStack(spacing: 10) {
                    ForEach(rows) { habit in
                        HabitDotRow(habit: habit)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TODAY")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(WidgetDesign.textSecondary)

            Spacer()

            Text("\(entry.completedCount) of \(entry.totalCount)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetDesign.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "leaf")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(WidgetDesign.sage)
            Text("Begin a habit in Stillhabit")
                .font(.system(size: 12))
                .foregroundStyle(WidgetDesign.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct HabitDotRow: View {
    let habit: HabitSnapshot

    private var accent: Color { Color(hex: habit.colorHex) }

    var body: some View {
        HStack(spacing: 12) {
            Text(habit.title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(WidgetDesign.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                // Past 6 days — quiet, non-interactive dots.
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(pastDay(index) ? accent.opacity(0.85) : WidgetDesign.textSecondary.opacity(0.18))
                        .frame(width: 7, height: 7)
                }

                // Today — fixed 24pt interactive dot; only fill/checkmark change.
                Button(intent: ToggleHabitIntent(habitID: habit.id)) {
                    ZStack {
                        Circle()
                            .fill(accent)
                            .opacity(habit.isDoneToday ? 1 : 0)
                        Circle()
                            .strokeBorder(accent.opacity(0.9), lineWidth: 1.5)
                            .opacity(habit.isDoneToday ? 0 : 1)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WidgetDesign.onAccent)
                            .opacity(habit.isDoneToday ? 1 : 0)
                    }
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .invalidatableContent()
                .accessibilityLabel(habit.title)
                .accessibilityValue(habit.isDoneToday ? "Completed today" : "Not completed today")
            }
        }
        .frame(height: 26)
    }

    /// Completion flag for one of the 6 days preceding today (oldest first).
    private func pastDay(_ index: Int) -> Bool {
        guard habit.trail.count == 7 else { return false }
        return habit.trail[index]
    }
}
