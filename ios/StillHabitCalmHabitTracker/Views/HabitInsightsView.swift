//
//  HabitInsightsView.swift
//  StillHabitCalmHabitTracker
//
//  Two quiet observations about a habit — how often it lands, and when.
//  No charts, no scoring, no red or green. Just a number and a time of day,
//  fading in gently once the rest of the page has settled.
//

import SwiftUI

struct HabitInsightsView: View {
    let habit: Habit
    let accent: Color

    @State private var hasAppeared: Bool = false

    private let windowDays: Int = 30

    private var rate: Double { habit.completionRatePercentage(for: windowDays) }
    private var ratePercent: Int { Int((rate * 100).rounded()) }
    private var pattern: TimeOfDayPattern? { habit.timeOfDayPattern(for: windowDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Insights")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 12) {
                completionRateCard
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                    .animation(.easeOut(duration: 0.55).delay(0.1), value: hasAppeared)

                timeContextCard
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                    .animation(.easeOut(duration: 0.55).delay(0.22), value: hasAppeared)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
        }
    }

    // MARK: - Card 1 · Completion rate

    private var completionRateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(ratePercent)%")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(ratePercent)))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: ratePercent)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("Success rate over the last 30 days.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(InsightCard(accent: accent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Completion rate")
        .accessibilityValue("\(ratePercent) percent over the last 30 days")
    }

    // MARK: - Card 2 · Time context

    private var timeContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: pattern?.symbolName ?? "clock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(pattern == nil ? DesignSystem.Colors.textSecondary : accent)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .frame(height: 34, alignment: .leading)

            Text(timeContextCopy)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeOut(duration: 0.4), value: pattern)
        .modifier(InsightCard(accent: accent))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time of day")
        .accessibilityValue(timeContextCopy)
    }

    /// Observational copy — a noticing, not an instruction.
    private var timeContextCopy: String {
        guard let pattern else {
            return "A few more completions and a time of day will start to show."
        }
        return "You naturally gravitate toward completing this in the \(pattern.inlineName)."
    }
}

// MARK: - Shared card chrome

/// The muted surface both insight cards sit on: the app's elevated card tone
/// warmed by the faintest breath of the habit's accent, with a soft radius.
private struct InsightCard: ViewModifier {
    let accent: Color

    private var cornerRadius: CGFloat { 18 }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(accent.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(accent.opacity(0.14), lineWidth: 0.5)
                    }
            }
            .softShadow()
    }
}

#Preview {
    HabitInsightsView(
        habit: Habit(title: "Morning stretch", colorHex: "C8826D"),
        accent: DesignSystem.Colors.terracotta
    )
    .padding(24)
    .background(DesignSystem.Colors.background)
}
