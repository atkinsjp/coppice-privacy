//
//  HabitDetailView.swift
//  Stillhabit
//
//  Progressive disclosure: a quiet, full-screen look at one habit.
//  An interactive 90-day heatmap and exactly three numbers. Nothing else.
//

import SwiftUI
import SwiftData

struct HabitDetailView: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var displayedCurrentStreak: Int = 0
    @State private var displayedBestStreak: Int = 0
    @State private var displayedTotal: Int = 0
    @State private var hasAnimatedIn: Bool = false

    /// Local editing state for the cadence. Seeded from the habit on appear;
    /// committed back to the habit (preserving all `completedDates`) whenever
    /// the user changes the schedule, so streaks recompute live.
    @State private var editingCadence: HabitCadence = .daily
    @State private var editingWeekdays: Set<Int> = []
    @State private var editingWeeklyGoal: Int = 3

    private let dayCount = 90
    private let columns = 15

    private var accent: Color { DesignSystem.habitColor(forHex: habit.colorHex) }

    /// The trailing 90 calendar days, oldest first (today last).
    private var trailDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private var sinceLine: String {
        "Since " + habit.createdAt.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        ZStack {
            backgroundWash

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    header

                    MonthRhythmGridView(habit: habit, accent: accent)

                    heatmap

                    statsCapsule

                    scheduleSection
                }
                .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
                .padding(.top, 28)
                .padding(.bottom, 48)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                commitCadenceIfNeeded()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(DesignSystem.Colors.card, in: Circle())
                    .softShadow()
            }
            .frame(width: 44, height: 44)
            .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.textSecondary))
            .padding(.top, 16)
            .padding(.trailing, DesignSystem.Layout.horizontalPadding - 4)
            .accessibilityLabel("Close")
        }
        .presentationBackground(DesignSystem.Colors.background)
        .onAppear {
            seedCadenceEditor()
            animateStatsIn()
        }
    }

    // MARK: - Background

    /// Warm ivory melting into the faintest breath of the habit's color.
    private var backgroundWash: some View {
        ZStack {
            DesignSystem.Colors.background

            LinearGradient(
                colors: [accent.opacity(0), accent.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)

            Text(habit.title)
                .font(DesignSystem.Typography.largeHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.trailing, 44)

            Text(sinceLine)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(habit.typeSummary)
                .font(DesignSystem.Typography.smallNumber)
                .foregroundStyle(accent)
                .padding(.top, 2)
        }
    }

    // MARK: - Schedule editor

    /// Inline cadence editor. Changing the schedule never touches
    /// `completedDates` — it only updates how completions are interpreted, so
    /// all historical progress is preserved and current/best streaks
    /// recalculate against the new schedule going forward.
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SCHEDULE")
                    .font(DesignSystem.Typography.overline)
                    .tracking(1.6)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Text(habit.cadenceSummary)
                    .font(DesignSystem.Typography.smallNumber)
                    .foregroundStyle(accent)
                    .animation(.easeOut(duration: 0.2), value: editingCadence)
            }

            CadencePicker(
                cadence: $editingCadence,
                selectedWeekdays: $editingWeekdays,
                weeklyGoal: $editingWeeklyGoal,
                accent: accent,
                label: "Edit frequency"
            )
        }
        .padding(20)
        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.5)
        }
        .softShadow()
        .onChange(of: editingCadence) { _, _ in commitCadenceIfNeeded() }
        .onChange(of: editingWeekdays) { _, _ in commitCadenceIfNeeded() }
        .onChange(of: editingWeeklyGoal) { _, _ in commitCadenceIfNeeded() }
    }

    /// Seeds the local editor state from the habit's stored cadence so the
    /// picker shows the current schedule before the user touches anything.
    private func seedCadenceEditor() {
        editingCadence = habit.cadence
        switch habit.cadence {
        case .daily:
            editingWeekdays = []
            editingWeeklyGoal = 3
        case .specificDays(let weekdays):
            editingWeekdays = Set(weekdays)
            editingWeeklyGoal = 3
        case .weeklyTarget(let target):
            editingWeekdays = []
            editingWeeklyGoal = target
        }
    }

    // MARK: - 90-day interactive heatmap

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LAST 90 DAYS")
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns),
                spacing: 5
            ) {
                ForEach(trailDates, id: \.self) { date in
                    heatmapCell(for: date)
                }
            }
        }
    }

    private func heatmapCell(for date: Date) -> some View {
        let progress = habit.progress(on: date)
        let isDone = progress >= 1
        let isToday = Calendar.current.isDateInToday(date)

        // Dynamic fill: 0% = faint background wash, 1–99% = accent shaded
        // proportionally, 100%+ = solid accent.
        let fillOpacity = heatmapFillOpacity(for: progress)
        let fill = isDone ? accent : accent.opacity(fillOpacity)

        return Button {
            toggleDay(date)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isDone ? DesignSystem.Colors.onAccent.opacity(0.6) : accent.opacity(0.7),
                                lineWidth: 1.5
                            )
                    }
                }
        }
        .buttonStyle(.stillTactileWave(accent: accent))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isDone)
        .animation(.easeOut(duration: 0.25), value: progress)
        .accessibilityLabel(date.formatted(.dateTime.month(.wide).day()))
        .accessibilityValue(heatmapAccessibilityValue(progress: progress))
        .accessibilityHint("Double tap to toggle")
    }

    /// Maps a 0...1 completion fraction to the heatmap cell's fill opacity:
    /// 0 → faint background wash (0.15); 0.01–0.99 → interpolated between
    /// 0.18 and 0.92 so partial days read as a visibly lighter shade of the
    /// accent, scaling smoothly with progress; 1.0 is rendered as a solid
    /// accent by the caller.
    private func heatmapFillOpacity(for progress: Double) -> Double {
        guard progress > 0 else { return 0.15 }
        if progress >= 1 { return 1 }
        let eased = 0.18 + (progress * 0.74)
        return min(eased, 0.92)
    }

    /// VoiceOver value for a heatmap cell, reflecting partial progress for
    /// numeric/duration habits (e.g. "64% complete") and a binary state for
    /// check-in habits.
    private func heatmapAccessibilityValue(progress: Double) -> String {
        if progress >= 1 { return "Completed" }
        if progress <= 0 { return "Not completed" }
        let pct = Int((progress * 100).rounded())
        return "\(pct)% complete"
    }

    /// Toggles the given calendar day in the habit's completion history.
    /// The wave button style fires the medium haptic on release.
    private func toggleDay(_ date: Date) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            habit.toggleCompletion(on: date)
        }
        try? modelContext.save()
        SharedStore.notifyWidgets()
        refreshStreaks()
    }

    /// Recomputes the displayed streak/total numbers from the habit's current
    /// cadence and completion history. Used after both a completion toggle and
    /// a cadence change so the three numbers always reflect the new schedule.
    private func refreshStreaks() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            displayedCurrentStreak = habit.currentStreak
            displayedBestStreak = habit.bestStreak
            displayedTotal = habit.totalCompletions
        }
    }

    // MARK: - Three numbers, one quiet capsule

    private var statsCapsule: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(value: displayedCurrentStreak, label: "Current streak")
            stat(value: displayedBestStreak, label: "Best streak")
            stat(value: displayedTotal, label: "Days completed")
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 26)
        .background(DesignSystem.Colors.card, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(DesignSystem.Colors.textSecondary.opacity(0.35), lineWidth: 0.5)
        }
        .softShadow()
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .contentTransition(.numericText(value: Double(value)))
                .monospacedDigit()

            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Gracefully rolls the three numbers up from zero, gently staggered.
    private func animateStatsIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true

        let targets = (habit.currentStreak, habit.bestStreak, habit.totalCompletions)

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                displayedCurrentStreak = targets.0
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                displayedBestStreak = targets.1
            }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                displayedTotal = targets.2
            }
        }
    }

    // MARK: - Cadence commit

    /// Resolves the local editor state into a final `HabitCadence` (empty
    /// specific-days falls back to `.daily`, the weekly goal is clamped) and,
    /// only if the schedule actually changed, writes it back to the habit —
    /// **without touching `completedDates`** — then saves, reloads widgets, and
    /// refreshes the displayed streaks so the new schedule is reflected
    /// immediately while all past completions are preserved. Called live as
    /// the user edits (so streaks recompute dynamically) and again on close.
    private func commitCadenceIfNeeded() {
        let resolved: HabitCadence
        switch editingCadence {
        case .daily:
            resolved = .daily
        case .specificDays:
            let sorted = editingWeekdays.sorted()
            resolved = sorted.isEmpty ? .daily : .specificDays(sorted)
        case .weeklyTarget:
            resolved = .weeklyTarget(max(1, min(editingWeeklyGoal, 6)))
        }

        guard resolved != habit.cadence else { return }

        habit.cadence = resolved
        try? modelContext.save()
        SharedStore.notifyWidgets()
        refreshStreaks()
    }
}

#Preview {
    HabitDetailView(habit: Habit(title: "Morning stretch", colorHex: "C8826D"))
        .modelContainer(for: Habit.self, inMemory: true)
}
