//
//  HabitRowView.swift
//  Stillhabit
//
//  A floating habit card. Press and hold (0.4s) or swipe right to complete.
//  Swipe left to reveal quiet actions (rest / delete).
//

import SwiftUI

struct HabitRowView: View {
    let habit: Habit
    /// When true (Today list), `.weeklyTarget` habits render a quiet
    /// "x of y this week" sub-label and gently fade once the target is met.
    var showsWeeklyProgress: Bool = false
    var onOpen: () -> Void = {}
    var onRest: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var dragOffset: CGFloat = 0
    @State private var isPressing = false
    @State private var isRevealed = false
    @State private var waveTick = 0

    /// Distance the card must travel rightward to count as a completion swipe.
    private let completionThreshold: CGFloat = 88
    /// Width of the hidden trailing action area.
    private let actionsWidth: CGFloat = 112

    private var accent: Color { Color(hex: habit.colorHex) }
    private var isDoneToday: Bool { habit.isCompleted(on: Date()) }

    /// Whether this card should render in its completed/faded state. For
    /// `.weeklyTarget` habits, the week's target being met counts as done
    /// even if today itself isn't logged.
    private var isEffectivelyDone: Bool {
        isDoneToday || habit.weeklyTargetMet
    }

    /// Quiet sub-label for `.weeklyTarget` habits, e.g. "2 of 3 this week".
    private var weeklyProgressLabel: String? {
        guard showsWeeklyProgress, case .weeklyTarget(let target) = habit.cadence else { return nil }
        let done = habit.completionsThisWeek()
        return "\(min(done, target)) of \(target) this week"
    }

    /// The one spring used for every card transformation.
    private var cardSpring: Animation { .spring(response: 0.35, dampingFraction: 0.7) }

    private var currentOffset: CGFloat {
        (isRevealed ? -actionsWidth : 0) + dragOffset
    }

    private var streakLabel: String? {
        let streak = habit.currentStreak
        return streak > 0 ? "\(streak)d" : nil
    }

    /// Quiet line describing when this habit was last completed, e.g.
    /// "Today at 3:42 PM" or "Jul 15 at 9:12 AM". Entries stored at exact
    /// midnight (logged from the heatmap grid) omit the meaningless time.
    private var lastCompletionLabel: String? {
        guard let last = habit.lastCompletion else { return nil }
        let calendar = Calendar.current
        let dayPart: String
        if calendar.isDateInToday(last) {
            dayPart = "Today"
        } else if calendar.isDateInYesterday(last) {
            dayPart = "Yesterday"
        } else {
            dayPart = last.formatted(.dateTime.month(.abbreviated).day())
        }
        if last == calendar.startOfDay(for: last) {
            return dayPart
        }
        return "\(dayPart) at \(last.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        ZStack {
            swipeHint
            quickActions
            card
        }
    }

    // MARK: - Card

    private var card: some View {
        HStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.onAccent)
                .opacity(isDoneToday ? 1 : 0)
                .frame(width: isDoneToday ? 24 : 0, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(isEffectivelyDone ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let weeklyProgressLabel {
                    Text(weeklyProgressLabel)
                        .font(DesignSystem.Typography.smallNumber)
                        .foregroundStyle(
                            isEffectivelyDone
                                ? DesignSystem.Colors.onAccent.opacity(0.72)
                                : DesignSystem.Colors.textSecondary
                        )
                        .transition(.opacity)
                } else if let lastCompletionLabel {
                    Text(lastCompletionLabel)
                        .font(DesignSystem.Typography.smallNumber)
                        .foregroundStyle(
                            isEffectivelyDone
                                ? DesignSystem.Colors.onAccent.opacity(0.72)
                                : DesignSystem.Colors.textSecondary
                        )
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let streakLabel {
                Text(streakLabel)
                    .font(DesignSystem.Typography.smallNumber)
                    .foregroundStyle(
                        isEffectivelyDone
                            ? DesignSystem.Colors.onAccent.opacity(0.72)
                            : DesignSystem.Colors.textSecondary
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        .background(isEffectivelyDone ? accent : DesignSystem.Colors.card)
        .clipShape(.rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .softShadow()
        .tactileWave(accent: accent, trigger: waveTick)
        .scaleEffect(isPressing ? 0.97 : 1)
        .offset(x: currentOffset)
        .animation(cardSpring, value: isEffectivelyDone)
        .onTapGesture {
            if isRevealed {
                withAnimation(cardSpring) { isRevealed = false }
            } else {
                waveTick += 1
                onOpen()
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            if isRevealed {
                withAnimation(cardSpring) { isRevealed = false }
            } else {
                toggle()
            }
        } onPressingChanged: { pressing in
            withAnimation(cardSpring) { isPressing = pressing }
        }
        .simultaneousGesture(drag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.title)
        .accessibilityValue(
            isEffectivelyDone
                ? "Completed today\(lastCompletionLabel.map { ", \($0)" } ?? "")"
                : "Not completed today\(lastCompletionLabel.map { ", last done \($0)" } ?? "")"
        )
        .accessibilityAction(named: "Open details") { onOpen() }
        .accessibilityAction(named: isDoneToday ? "Mark incomplete" : "Mark complete") { toggle() }
        .accessibilityAction(named: "Let it rest") { onRest() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    // MARK: - Swipe-right completion hint

    private var swipeHint: some View {
        HStack {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .opacity(hintProgress)
                .scaleEffect(0.6 + 0.4 * hintProgress)
            Spacer()
        }
        .padding(.leading, 26)
        .accessibilityHidden(true)
    }

    private var hintProgress: CGFloat {
        min(max(currentOffset / completionThreshold, 0), 1)
    }

    // MARK: - Hidden quiet actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                withAnimation(cardSpring) { isRevealed = false }
                onRest()
            } label: {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.textSecondary))
            .accessibilityLabel("Let \(habit.title) rest")

            Button {
                withAnimation(cardSpring) { isRevealed = false }
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.terracotta)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.terracotta))
            .accessibilityLabel("Delete \(habit.title)")
        }
        .padding(.trailing, 4)
        .opacity(currentOffset < -12 ? 1 : 0)
        .animation(cardSpring, value: isRevealed)
    }

    // MARK: - Gestures

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                let translation = value.translation.width
                if isRevealed {
                    dragOffset = min(max(translation, 0), actionsWidth)
                } else if translation >= 0 {
                    dragOffset = translation <= completionThreshold
                        ? translation
                        : completionThreshold + (translation - completionThreshold) * 0.25
                } else {
                    dragOffset = max(translation, -actionsWidth - 24)
                }
            }
            .onEnded { value in
                let translation = value.translation.width
                if isRevealed {
                    if translation > 28 {
                        withAnimation(cardSpring) { isRevealed = false }
                    }
                } else if translation >= completionThreshold {
                    if !isDoneToday { toggle() }
                } else if translation < -actionsWidth * 0.5 {
                    withAnimation(cardSpring) { isRevealed = true }
                }
                withAnimation(cardSpring) { dragOffset = 0 }
            }
    }

    // MARK: - Actions

    /// Flips today's completion. The tactile wave modifier fires the medium
    /// haptic pulse and the outward ripple the instant `waveTick` changes.
    private func toggle() {
        waveTick += 1
        withAnimation(cardSpring) {
            habit.toggleCompletion(on: Date())
        }
        SharedStore.notifyWidgets()
    }
}
