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

    private let dayCount = 90
    private let columns = 15

    private var accent: Color { Color(hex: habit.colorHex) }

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

                    heatmap

                    statsCapsule
                }
                .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
                .padding(.top, 28)
                .padding(.bottom, 48)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
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
        .onAppear(perform: animateStatsIn)
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
        let isDone = habit.isCompleted(on: date)
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            toggleDay(date)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(isDone ? accent : accent.opacity(0.15))
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
        .accessibilityLabel(date.formatted(.dateTime.month(.wide).day()))
        .accessibilityValue(isDone ? "Completed" : "Not completed")
        .accessibilityHint("Double tap to toggle")
    }

    /// Toggles the given calendar day in the habit's completion history.
    /// The wave button style fires the medium haptic on release.
    private func toggleDay(_ date: Date) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            habit.toggleCompletion(on: date)
        }
        try? modelContext.save()
        SharedStore.notifyWidgets()

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
}

#Preview {
    HabitDetailView(habit: Habit(title: "Morning stretch", colorHex: "C8826D"))
        .modelContainer(for: Habit.self, inMemory: true)
}
