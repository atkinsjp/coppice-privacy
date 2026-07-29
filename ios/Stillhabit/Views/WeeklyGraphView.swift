//
//  WeeklyGraphView.swift
//  Stillhabit
//
//  A 7-day completion bar graph. Each scheduled habit gets a row of seven
//  vertical bars (one per trailing day); the bar height reflects that day's
//  exact completion progress (0–100%). An aggregate summary crowns the top.
//  Quiet, earthy, and consistent with the rest of the app.
//

import SwiftUI
import SwiftData

struct WeeklyGraphView: View {

    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.createdAt)
    private var allHabits: [Habit]

    @Environment(\.dismiss) private var dismiss

    /// Whether the entrance animation has played. Guards against re-triggering
    /// on re-renders so bars only grow up once, on first appear.
    @State private var hasAnimatedIn = false

    private let dayCount = 7

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()
    }

    /// The trailing 7 calendar days, oldest first (today last).
    private var trailDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    /// The 7 calendar days before the current trailing window — the previous
    /// week, oldest first. Used to compare week-over-week performance.
    private var previousWeekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -dayCount, to: today) else { return [] }
        return (0..<dayCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: weekAgo)
        }
    }

    /// Only habits with a real schedule this week are charted — archived and
    /// never-scheduled habits are excluded so the graph stays meaningful.
    private var graphHabits: [Habit] {
        allHabits.filter { habit in
            trailDates.contains { habit.isScheduled(on: $0) }
        }
    }

    /// The average completion ratio for a habit across the given dates,
    /// counting only scheduled day-slots. Returns 0 when the habit had no
    /// scheduled days in that window (e.g. it was created this week).
    private func completionRatio(for habit: Habit, over dates: [Date]) -> Double {
        let scheduled = dates.filter { habit.isScheduled(on: $0) }
        guard !scheduled.isEmpty else { return 0 }
        let summed = scheduled.reduce(0.0) { $0 + habit.progress(on: $1) }
        return summed / Double(scheduled.count)
    }

    /// Whether the habit had any scheduled days in the previous week window.
    /// Used to decide whether a trend arrow is meaningful — a habit created
    /// this week has no prior baseline to compare against.
    private func hasPreviousWeekBaseline(_ habit: Habit) -> Bool {
        previousWeekDates.contains { habit.isScheduled(on: $0) && $0 >= habit.createdAt }
    }

    /// The signed change in completion ratio vs last week, in the range -1...1.
    /// Positive means improvement; negative means decline.
    private func weekOverWeekDelta(_ habit: Habit) -> Double {
        completionRatio(for: habit, over: trailDates) - completionRatio(for: habit, over: previousWeekDates)
    }

    /// The total scheduled day-slots across all graphed habits this week.
    private var totalSlots: Int {
        graphHabits.reduce(0) { acc, habit in
            acc + trailDates.filter { habit.isScheduled(on: $0) }.count
        }
    }

    /// How many of those slots were completed (full progress).
    private var completedSlots: Int {
        graphHabits.reduce(0) { acc, habit in
            acc + trailDates.filter { habit.isScheduled(on: $0) && habit.progress(on: $0) >= 1 }.count
        }
    }

    /// The week's average completion ratio across all scheduled slots.
    private var weekCompletionRatio: Double {
        guard totalSlots > 0 else { return 0 }
        let summed = graphHabits.reduce(0.0) { acc, habit in
            acc + trailDates.reduce(0.0) { dayAcc, date in
                habit.isScheduled(on: date) ? dayAcc + habit.progress(on: date) : dayAcc
            }
        }
        return summed / Double(totalSlots)
    }

    private var weekPercentageText: String {
        "\(Int((weekCompletionRatio * 100).rounded()))%"
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if graphHabits.isEmpty {
                        emptyState
                    } else {
                        summaryCard
                        graphSection
                        legend
                    }
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
        .onAppear { animateBarsIn() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLine)
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("This Week")
                .font(DesignSystem.Typography.largeHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.trailing, 44)

            Text("Seven days of quiet progress")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(weekPercentageText)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.sage)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: weekCompletionRatio * 100))

                Text("Week completion")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                statChip(
                    label: "Completed",
                    value: "\(completedSlots)",
                    accent: DesignSystem.Colors.sage
                )
                statChip(
                    label: "Scheduled",
                    value: "\(totalSlots)",
                    accent: DesignSystem.Colors.textSecondary
                )
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.sage.opacity(0.18), lineWidth: 0.5)
        }
        .softShadow()
    }

    private func statChip(label: String, value: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DesignSystem.Typography.smallNumber)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Graph

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LAST 7 DAYS")
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            VStack(spacing: DesignSystem.Layout.rowSpacing) {
                ForEach(graphHabits, id: \.id) { habit in
                    habitRow(habit)
                }
            }
        }
    }

    /// One row of the graph: the habit name on the left, seven vertical bars
    /// on the right. Each bar's height is its day's completion progress.
    /// Unscheduled days render as a faint dashed placeholder so the rhythm of
    /// the week stays legible without implying failure.
    private func habitRow(_ habit: Habit) -> some View {
        let accent = Color(hex: habit.colorHex)

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                    trendArrow(for: habit)
                }
                Text(habit.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 78, alignment: .leading)
            }

            GeometryReader { geo in
                let barAreaHeight = geo.size.height
                let spacing: CGFloat = 6
                let barWidth = max(10, (geo.size.width - spacing * CGFloat(dayCount - 1)) / CGFloat(dayCount))

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(trailDates, id: \.self) { date in
                        barCell(
                            habit: habit,
                            date: date,
                            accent: accent,
                            barWidth: barWidth,
                            maxHeight: barAreaHeight
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: barAreaHeight, alignment: .bottom)
            }
            .frame(height: 88)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(accent.opacity(0.14), lineWidth: 0.5)
        }
        .softShadow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.title), \(habitWeeklySummary(habit))\(trendAccessibilitySuffix(habit))")
    }

    /// A single vertical bar for one habit-day. Height encodes progress 0–1.
    @ViewBuilder
    private func barCell(
        habit: Habit,
        date: Date,
        accent: Color,
        barWidth: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        let isScheduled = habit.isScheduled(on: date)
        let progress = habit.progress(on: date)
        let isToday = Calendar.current.isDateInToday(date)
        let animatedProgress = hasAnimatedIn ? progress : 0
        let barHeight = maxHeight * animatedProgress

        VStack(spacing: 4) {
            if isScheduled {
                RoundedRectangle(cornerRadius: 4)
                    .fill(progress >= 1 ? accent : accent.opacity(0.35 + animatedProgress * 0.5))
                    .frame(width: barWidth, height: max(barHeight, animatedProgress > 0 ? 3 : 0))
                    .overlay {
                        if isToday {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(accent.opacity(0.8), lineWidth: 1.2)
                                .frame(width: barWidth, height: max(barHeight, 3))
                        }
                    }
                    .animation(
                        .spring(response: 0.7, dampingFraction: 0.82)
                            .delay(staggerDelay(for: date)),
                        value: hasAnimatedIn
                    )
            } else {
                // Unscheduled day — a quiet dashed tick so the week keeps its shape.
                Capsule()
                    .strokeBorder(DesignSystem.Colors.textSecondary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: barWidth, height: 10)
            }

            dayLabel(for: date)
        }
        .frame(width: barWidth)
        .accessibilityHidden(true)
    }

    /// Short single-letter weekday label (M, T, W…). Today is rendered in the
    /// accent color to anchor the eye.
    private func dayLabel(for date: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let symbol = date.formatted(.dateTime.weekday(.narrow)).uppercased()
        return Text(symbol)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isToday ? DesignSystem.Colors.sage : DesignSystem.Colors.textSecondary.opacity(0.7))
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: DesignSystem.Colors.sage, label: "Completed")
            legendItem(color: DesignSystem.Colors.sage.opacity(0.4), label: "Partial")
            legendDashed(label: "Not scheduled")
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendDashed(label: String) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .strokeBorder(DesignSystem.Colors.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DesignSystem.Colors.sage)

            Text("No habits scheduled this week yet.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Once you add habits with a daily or weekly cadence, their completions will chart here.")
                .font(.system(size: 13))
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    // MARK: - Trend arrow

    /// A small up/down arrow showing whether this habit's completion ratio
    /// improved or declined versus the previous week. Rendered next to the
    /// habit's color dot. Habits with no prior-week baseline (created this
    /// week) show no arrow. An exactly-flat trend shows a quiet dash.
    @ViewBuilder
    private func trendArrow(for habit: Habit) -> some View {
        guard hasPreviousWeekBaseline(habit) else {
            return AnyView(EmptyView())
        }
        let delta = weekOverWeekDelta(habit)
        let direction = TrendDirection.from(delta)
        return AnyView(
            Image(systemName: direction.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(direction.color)
                .opacity(hasAnimatedIn ? 1 : 0)
                .offset(y: hasAnimatedIn ? 0 : -3)
                .animation(
                    .easeOut(duration: 0.5)
                        .delay(0.35),
                    value: hasAnimatedIn
                )
                .accessibilityLabel(direction.accessibilityLabel)
        )
    }

    /// The week-over-week trend classification for a single habit.
    private enum TrendDirection {
        case up, down, flat

        /// Threshold below which a delta is considered flat (within 5%).
        private static let flatThreshold: Double = 0.05

        static func from(_ delta: Double) -> TrendDirection {
            if delta > flatThreshold { return .up }
            if delta < -flatThreshold { return .down }
            return .flat
        }

        var symbol: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .flat: return "minus"
            }
        }

        var color: Color {
            switch self {
            case .up: return DesignSystem.Colors.sage
            case .down: return DesignSystem.Colors.terracotta
            case .flat: return DesignSystem.Colors.textSecondary.opacity(0.6)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .up: return "improved from last week"
            case .down: return "declined from last week"
            case .flat: return "same as last week"
            }
        }
    }

    // MARK: - Helpers

    /// Per-habit VoiceOver summary, e.g. "4 of 6 days completed this week".
    private func habitWeeklySummary(_ habit: Habit) -> String {
        let scheduled = trailDates.filter { habit.isScheduled(on: $0) }
        let completed = scheduled.filter { habit.progress(on: $0) >= 1 }
        guard !scheduled.isEmpty else { return "no scheduled days this week" }
        return "\(completed.count) of \(scheduled.count) days completed this week"
    }

    /// VoiceOver suffix appended to the row label describing the week-over-week
    /// trend, e.g. ", improved from last week". Empty when there is no
    /// prior-week baseline to compare against.
    private func trendAccessibilitySuffix(_ habit: Habit) -> String {
        guard hasPreviousWeekBaseline(habit) else { return "" }
        let direction = TrendDirection.from(weekOverWeekDelta(habit))
        return ", \(direction.accessibilityLabel)"
    }

    /// Staggered entrance delay so bars rise in a gentle left-to-right wave.
    /// Older days (leftmost) animate first; today animates last.
    private func staggerDelay(for date: Date) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayOffset = calendar.dateComponents([.day], from: today, to: date).day ?? 0
        return Double(max(0, dayOffset)) * 0.06
    }

    /// Grows all bars from zero up to their true progress on appear, with a
    /// gentle staggered spring so the graph feels alive rather than static.
    private func animateBarsIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
    }
}

#Preview {
    WeeklyGraphView()
        .modelContainer(for: Habit.self, inMemory: true)
}
