//
//  MonthRhythmGridView.swift
//  Stillhabit
//
//  A compact, week-aligned 30-day grid — the habit's short-term rhythm at a
//  glance. Read-only by design: the 90-day map below remains the editable one.
//

import SwiftUI

struct MonthRhythmGridView: View {
    let habit: Habit
    let accent: Color

    @State private var hasAppeared: Bool = false

    private let dayCount: Int = 30
    private let cellSpacing: CGFloat = 6

    private var calendar: Calendar { Calendar.current }

    /// The trailing 30 calendar days, oldest first (today last).
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    /// Empty leading slots so the first day lands under its true weekday column.
    private var leadingBlanks: Int {
        guard let first = days.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Single-letter weekday headers, rotated to the user's locale start-of-week.
    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    /// Slots to render: nil = alignment padding, Date = a real day.
    private var slots: [Date?] {
        Array(repeating: nil, count: leadingBlanks) + days.map { Optional($0) }
    }

    private var completedCount: Int {
        days.filter { habit.progress(on: $0) >= 1 }.count
    }

    /// Completion rate across the trailing 30 days, rounded to a whole percent.
    private var completionPercent: Int {
        guard dayCount > 0 else { return 0 }
        return Int(((Double(completedCount) / Double(dayCount)) * 100).rounded())
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("LAST 30 DAYS")
                    .font(DesignSystem.Typography.overline)
                    .tracking(1.6)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Text("\(completedCount) of \(dayCount)")
                    .font(DesignSystem.Typography.smallNumber)
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(completedCount)))
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: completedCount)

                percentBadge
            }

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.7))
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: gridColumns, spacing: cellSpacing) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    if let date = slot {
                        cell(for: date, index: index)
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last 30 days rhythm")
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
        }
    }

    /// A quiet capsule showing the 30-day completion rate.
    private var percentBadge: some View {
        Text("\(completionPercent)%")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(completionPercent)))
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.14))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
                    }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: completionPercent)
            .accessibilityElement()
            .accessibilityLabel("30 day completion rate")
            .accessibilityValue("\(completionPercent) percent")
    }

    private func cell(for date: Date, index: Int) -> some View {
        let progress = habit.progress(on: date)
        let isDone = progress >= 1
        let isToday = calendar.isDateInToday(date)

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isDone ? accent : accent.opacity(fillOpacity(for: progress)))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            isDone ? DesignSystem.Colors.onAccent.opacity(0.6) : accent.opacity(0.7),
                            lineWidth: 1.5
                        )
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.65)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.78)
                    .delay(Double(index) * 0.012),
                value: hasAppeared
            )
            .animation(.easeOut(duration: 0.25), value: progress)
            .accessibilityElement()
            .accessibilityLabel(date.formatted(.dateTime.month(.wide).day()))
            .accessibilityValue(accessibilityValue(progress: progress))
    }

    /// Maps a 0...1 completion fraction to a cell's accent opacity, matching
    /// the 90-day map's shading so both grids read as one visual language.
    private func fillOpacity(for progress: Double) -> Double {
        guard progress > 0 else { return 0.12 }
        if progress >= 1 { return 1 }
        return min(0.18 + (progress * 0.74), 0.92)
    }

    private func accessibilityValue(progress: Double) -> String {
        if progress >= 1 { return "Completed" }
        if progress <= 0 { return "Not completed" }
        return "\(Int((progress * 100).rounded()))% complete"
    }
}

#Preview {
    MonthRhythmGridView(
        habit: Habit(title: "Morning stretch", colorHex: "C8826D"),
        accent: DesignSystem.Colors.terracotta
    )
    .padding(24)
    .background(DesignSystem.Colors.background)
}
