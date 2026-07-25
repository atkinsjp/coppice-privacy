//
//  HabitRowView.swift
//  Stillhabit
//
//  A floating habit card. Behavior branches by habit type:
//  - checkIn:  press-and-hold (0.4s) or swipe right to complete.
//  - numeric:  quick-add pills on the right; a soft liquid fill grows
//              left→right with today's progress. Reaching the target
//              marks the day complete and fires the signature wave.
//  - duration: a play/pause focus timer. Tapping play expands the card
//              to reveal a calm countdown clock; the border breathes
//              while running. At zero the day is logged complete with
//              a medium haptic and an outward ripple.
//
//  Swipe left always reveals the quiet actions (rest / delete).
//

import SwiftUI
import SwiftData
import Combine

struct HabitRowView: View {
    let habit: Habit
    /// When true (Today list), `.weeklyTarget` habits render a quiet
    /// "x of y this week" sub-label and gently fade once the target is met.
    var showsWeeklyProgress: Bool = false
    var onOpen: () -> Void = {}
    var onRest: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    @State private var dragOffset: CGFloat = 0
    @State private var isPressing = false
    @State private var isRevealed = false
    @State private var waveTick = 0

    // Duration focus-timer state.
    /// Whether the countdown clock is currently expanded into view.
    @State private var isTimerExpanded = false
    /// The remaining seconds shown on the clock. Updated by the tick.
    @State private var displayedRemainingSeconds: Double = 0
    /// Drives the breathing border while the timer runs.
    @State private var borderPulse = false

    // Why-anchor reveal state.
    /// For numeric habits: transiently true after a quick-add tap so the
    /// `whyString` surfaces as a reflective moment, then fades on its own.
    @State private var numericWhyRevealed = false
    /// Monotonic token used to cancel any pending auto-hide of the numeric
    /// why-anchor — each tap increments it, and only the latest-scheduled
    /// hide task is allowed to clear the flag.
    @State private var numericWhyHideToken = 0

    /// Whether the focus timer is actively running. Derived from the
    /// persisted `habit.timerStart` so the state survives navigation away
    /// from the view, the phone locking, and the app being killed — when the
    /// card re-appears it reads as running again if the habit still has a
    /// live start anchor.
    private var isTimerRunning: Bool { habit.timerStart != nil }

    /// Whether the `whyString` should be visible right now. Each habit type
    /// has its own trigger: check-in reveals on press-and-hold (the moment
    /// before completion), duration reveals while the focus timer is expanded,
    /// and numeric reveals transiently after a quick-add tap. A nil/empty
    /// `whyString` never reveals anything.
    private var isWhyRevealed: Bool {
        guard habit.hasWhyAnchor else { return false }
        switch habitType {
        case .checkIn:
            return isPressing
        case .duration:
            return isTimerExpanded
        case .numeric:
            return numericWhyRevealed
        }
    }

    /// Distance the card must travel rightward to count as a completion swipe.
    private let completionThreshold: CGFloat = 88
    /// Width of the hidden trailing action area.
    private let actionsWidth: CGFloat = 112

    private var accent: Color { Color(hex: habit.colorHex) }
    private var isDoneToday: Bool { habit.isCompleted(on: Date()) }

    private var habitType: HabitType { habit.type }

    /// Style for the reflective `whyString` line — SF Pro Text, 13pt, italic,
    /// in a soft slate-blue shade that reads as intimate without competing
    /// with the habit title or the accent fill.
    private var whyAnchorColor: Color {
        isEffectivelyDone
            ? DesignSystem.Colors.onAccent.opacity(0.78)
            : DesignSystem.Colors.slateBlue
    }

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

    /// Vertical spacing inside the card. Gives the why-anchor reveal and the
    /// expanded countdown clock room to breathe when present, collapses to a
    /// tight single row at rest.
    private var cardSpacing: CGFloat {
        (isTimerExpanded || isWhyRevealed) ? 14 : 0
    }

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
        .onAppear { seedTimerDisplay() }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            guard isTimerRunning else { return }
            tickTimer()
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: cardSpacing) {
            HStack(spacing: 0) {
                leadingContent
                Spacer(minLength: 12)
                trailingControl
            }

            if isWhyRevealed, let whyText = habit.whyAnchorText {
                whyAnchorView(whyText)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isTimerExpanded, case .duration = habitType {
                countdownClock
            }
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
        .background(cardBackground)
        .overlay { borderPulseOverlay }
        .clipShape(.rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .softShadow()
        .tactileWave(accent: accent, trigger: waveTick)
        .scaleEffect(isPressing ? 0.97 : 1)
        .offset(x: currentOffset)
        .animation(cardSpring, value: isEffectivelyDone)
        .animation(cardSpring, value: isTimerExpanded)
        .animation(cardSpring, value: habit.todayProgress)
        .animation(.easeInOut(duration: 0.4), value: isWhyRevealed)
        .contentShape(.rect)
        .onTapGesture {
            if isRevealed {
                withAnimation(cardSpring) { isRevealed = false }
            } else {
                waveTick += 1
                onOpen()
            }
        }
        .modifier(CompletionLongPressModifier(
            isEnabled: habitType.isCheckIn,
            isPressing: $isPressing,
            onComplete: { toggle() }
        ))
        .simultaneousGesture(drag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.title)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAction(named: "Open details") { onOpen() }
        .accessibilityAction(named: isDoneToday ? "Mark incomplete" : "Mark complete") { toggle() }
        .accessibilityAction(named: "Let it rest") { onRest() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var accessibilityValueText: String {
        let base = isEffectivelyDone
            ? "Completed today\(lastCompletionLabel.map { ", \($0)" } ?? "")"
            : "Not completed today\(lastCompletionLabel.map { ", last done \($0)" } ?? "")"
        switch habitType {
        case .checkIn:
            return base
        case .numeric:
            return "\(base), \(habit.todayProgressLabel)"
        case .duration:
            return "\(base), \(habit.todayProgressLabel)"
        }
    }

    // MARK: - Why anchor

    /// The reflective intentionality line — SF Pro Text, 13pt italic, in a
    /// soft slate-blue that reads as intimate without competing with the
    /// title or the accent fill. Sits right above the completion control as a
    /// quiet moment of grounding right before the user logs progress.
    private func whyAnchorView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .italic()
            .foregroundStyle(whyAnchorColor)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Your why: \(text)")
    }

    // MARK: - Leading content (shared)

    private var leadingContent: some View {
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

                subLabel
            }
        }
    }

    /// Quiet secondary line beneath the title. Weekly-target habits show
    /// their weekly progress; numeric/duration habits show today's progress
    /// toward the target; otherwise the last-completion timestamp.
    @ViewBuilder
    private var subLabel: some View {
        if let weeklyProgressLabel {
            subLabelText(weeklyProgressLabel)
        } else if habitType.showsInlineProgress {
            subLabelText(habit.todayProgressLabel)
        } else if let lastCompletionLabel {
            subLabelText(lastCompletionLabel)
        }
    }

    private func subLabelText(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.smallNumber)
            .foregroundStyle(
                isEffectivelyDone
                    ? DesignSystem.Colors.onAccent.opacity(0.72)
                    : DesignSystem.Colors.textSecondary
            )
            .transition(.opacity)
    }

    // MARK: - Trailing control (branches by type)

    @ViewBuilder
    private var trailingControl: some View {
        switch habitType {
        case .checkIn:
            // No inline control — press-and-hold completes the card.
            EmptyView()
        case .numeric:
            numericQuickAddBar
        case .duration:
            playPauseButton
        }
    }

    // MARK: - Numeric quick-add bar

    /// A sleek row of `+value` pills on the right. The three step sizes are
    /// scaled to the habit's target so a tap always moves the fill a visible
    /// amount without overshooting. Tapping adds to today's logged value and
    /// the card's background fills left→right with the accent color; when the
    /// target is reached the day is marked complete and the wave fires.
    private var numericQuickAddBar: some View {
        HStack(spacing: 6) {
            ForEach(quickAddSteps, id: \.self) { step in
                Button {
                    addValue(step)
                } label: {
                    Text("+\(ValueFormatter.wholeOrDecimal(step))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isEffectivelyDone ? DesignSystem.Colors.onAccent : accent)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            Group {
                                if isEffectivelyDone {
                                    Capsule().fill(DesignSystem.Colors.onAccent.opacity(0.18))
                                } else {
                                    Capsule().fill(accent.opacity(0.14))
                                }
                            }
                        )
                }
                .buttonStyle(.stillTactileWave(accent: accent))
                .disabled(isEffectivelyDone)
                .opacity(isEffectivelyDone ? 0.45 : 1)
                .accessibilityLabel("Add \(ValueFormatter.wholeOrDecimal(step)) \(habit.numericUnit)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Three sensible step sizes relative to the target, deduped and clamped
    /// to at least 1. Roughly 10%, 25%, and 50% of the target, rounded to
    /// nice values (halves for small targets, integers otherwise).
    private var quickAddSteps: [Double] {
        let target = habit.numericTarget
        guard target > 0 else { return [1] }
        let useHalves = target <= 10
        let raw = [target * 0.1, target * 0.25, target * 0.5]
        var steps = raw.map { value -> Double in
            let v = useHalves ? (value * 2).rounded() / 2 : value.rounded()
            return max(1, v)
        }
        var seen = Set<Double>()
        steps = steps.filter { seen.insert($0).inserted }
        return steps.isEmpty ? [1] : steps
    }

    /// Appends a quick-add step to today's progress. The model marks the day
    /// complete automatically when the target is met; we fire the signature
    /// wave + haptic only on that completion transition.
    private func addValue(_ value: Double) {
        let wasDone = isEffectivelyDone
        habit.logProgress(value, on: Date())
        if !wasDone, isEffectivelyDone {
            waveTick += 1
        }
        saveAndNotify()
        revealNumericWhyAnchor()
    }

    /// Surfaces the `whyString` as a reflective moment after a numeric
    /// quick-add tap, then quietly fades it back out after ~2.5s so the
    /// card's resting state stays uncluttered. Each tap cancels any pending
    /// auto-hide so repeated taps keep the anchor visible without flickering.
    private func revealNumericWhyAnchor() {
        guard habit.hasWhyAnchor, !isEffectivelyDone else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            numericWhyRevealed = true
        }
        numericWhyHideToken += 1
        let token = numericWhyHideToken
        Task {
            try? await Task.sleep(for: .milliseconds(2500))
            guard token == numericWhyHideToken, !isEffectivelyDone else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.4)) {
                    if token == numericWhyHideToken {
                        numericWhyRevealed = false
                    }
                }
            }
        }
    }

    // MARK: - Duration focus timer

    /// The play/pause control. Tapping play expands the card to reveal the
    /// countdown clock and starts (or resumes) the timer; tapping pause
    /// stops it, persisting the elapsed seconds so progress survives.
    private var playPauseButton: some View {
        Button {
            isTimerRunning ? pauseTimer() : startTimer()
        } label: {
            Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isEffectivelyDone ? DesignSystem.Colors.onAccent : accent)
                .frame(width: 40, height: 40)
                .background(
                    Group {
                        if isEffectivelyDone {
                            Circle().fill(DesignSystem.Colors.onAccent.opacity(0.18))
                        } else {
                            Circle().fill(accent.opacity(0.14))
                        }
                    }
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.stillTactileWave(accent: accent))
        .disabled(isEffectivelyDone)
        .opacity(isEffectivelyDone ? 0.45 : 1)
        .accessibilityLabel(isTimerRunning ? "Pause focus timer" : "Start focus timer")
    }

    /// The inline, calming countdown clock — bold SF Pro Rounded, formatted
    /// as `m:ss`. Sits beneath the title row when the card is expanded.
    private var countdownClock: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(ValueFormatter.clockString(seconds: Int(displayedRemainingSeconds.rounded())))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isEffectivelyDone ? DesignSystem.Colors.onAccent : accent)
                .contentTransition(.numericText(value: displayedRemainingSeconds))
                .frame(minWidth: 96, alignment: .leading)

            Spacer(minLength: 8)

            // A whisper of the fill so far.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.onAccent.opacity(0.16))
                    Capsule()
                        .fill(isEffectivelyDone ? DesignSystem.Colors.onAccent : accent)
                        .frame(width: max(geo.size.width * habit.todayProgress, habit.todayProgress > 0 ? 4 : 0))
                }
            }
            .frame(height: 4)
        }
        .padding(.top, 2)
        .accessibilityLabel("Time remaining: \(Int(displayedRemainingSeconds.rounded())) seconds")
    }

    /// Starts (or resumes) the focus timer. Elapsed accumulated from previous
    /// paused runs lives in the habit's `logs`; this run is measured from now
    /// via the persisted `timerStart` anchor, so progress stays accurate across
    /// backgrounding, screen lock, and app kills.
    private func startTimer() {
        guard !isEffectivelyDone else { return }
        withAnimation(cardSpring) { isTimerExpanded = true }
        habit.timerStart = Date()
        saveAndNotify()
        startBorderPulse()
    }

    /// Pauses the timer: commits the elapsed seconds since `timerStart` to the
    /// habit's `logs`, clears the persisted anchor, and persists so progress
    /// survives across card interactions and app launches.
    private func pauseTimer() {
        guard let start = habit.timerStart else { return }
        let runElapsed = Date().timeIntervalSince(start)
        habit.timerStart = nil
        stopBorderPulse()
        if runElapsed > 0 {
            habit.logProgress(runElapsed, on: Date())
        }
        saveAndNotify()
    }

    /// Called every 0.2s while running. Computes the remaining seconds from
    /// accumulated logs + this run's elapsed time (derived from the persisted
    /// `timerStart` anchor), and completes the habit the instant the target is
    /// reached. Also reconciles completion if the timer ran past zero while the
    /// app was backgrounded.
    private func tickTimer() {
        guard let start = habit.timerStart else { return }
        let runElapsed = Date().timeIntervalSince(start)
        let totalElapsed = habit.loggedToday + runElapsed
        let remaining = max(0, habit.durationTargetSeconds - totalElapsed)
        displayedRemainingSeconds = remaining
        if remaining <= 0 {
            completeTimer()
        }
    }

    /// Logs the final delta needed to hit the target exactly, stops the timer,
    /// fires the medium haptic + signature wave ripple, and collapses the
    /// expanded clock back down after a quiet beat so the completed card
    /// settles on its own. Works whether completion was observed live or after
    /// returning from background.
    private func completeTimer() {
        guard let start = habit.timerStart else { return }
        let runElapsed = Date().timeIntervalSince(start)
        let totalElapsed = habit.loggedToday + runElapsed
        let deficit = max(0, habit.durationTargetSeconds - totalElapsed)
        habit.timerStart = nil
        stopBorderPulse()
        if deficit > 0 {
            habit.logProgress(deficit, on: Date())
        } else if !isDoneToday {
            // Safety net: ensure the day is marked complete even if rounding
            // left us a hair under the target.
            habit.completedDates.append(Date())
        }
        waveTick += 1
        saveAndNotify()
        displayedRemainingSeconds = 0
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(cardSpring) { isTimerExpanded = false }
        }
    }

    /// Seeds the displayed remaining time from persisted progress so the
    /// clock shows the right value the first time the card expands. If the
    /// timer is still running (the app was backgrounded or the card scrolled
    /// off-screen), the running elapsed is included so the clock is accurate
    /// the instant the card reappears.
    private func seedTimerDisplay() {
        guard case .duration = habitType else { return }
        let runningElapsed = habit.timerStart.map { Date().timeIntervalSince($0) } ?? 0
        let totalElapsed = habit.loggedToday + runningElapsed
        let remaining = max(0, habit.durationTargetSeconds - totalElapsed)
        displayedRemainingSeconds = remaining
        // If a timer is still anchored as running, reveal the expanded clock
        // and restart the breathing border so the UI reflects the live state.
        if habit.timerStart != nil, !isEffectivelyDone {
            if remaining <= 0 {
                // The timer elapsed past zero while the app was backgrounded
                // or killed — reconcile completion immediately.
                completeTimer()
            } else {
                isTimerExpanded = true
                startBorderPulse()
            }
        }
    }

    // MARK: - Breathing border

    @ViewBuilder
    private var borderPulseOverlay: some View {
        if isTimerRunning {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(accent.opacity(borderPulse ? 0.65 : 0.15), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    private func startBorderPulse() {
        borderPulse = true
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            borderPulse = false
        }
    }

    private func stopBorderPulse() {
        withAnimation(.easeOut(duration: 0.3)) {
            borderPulse = false
        }
    }

    // MARK: - Card background

    /// Completed cards fill with the accent. Numeric cards additionally show
    /// a soft liquid fill that grows left→right with today's progress. Other
    /// cards use the standard elevated card color.
    @ViewBuilder
    private var cardBackground: some View {
        if isEffectivelyDone {
            accent
        } else if case .numeric = habitType {
            ZStack(alignment: .leading) {
                DesignSystem.Colors.card
                GeometryReader { geo in
                    accent.opacity(0.22)
                        .frame(width: max(geo.size.width * habit.todayProgress, habit.todayProgress > 0 ? 4 : 0))
                }
            }
        } else {
            DesignSystem.Colors.card
        }
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
                } else if translation >= completionThreshold, habitType.isCheckIn {
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
        saveAndNotify()
    }

    /// Persists the current model state and asks widgets to refresh.
    private func saveAndNotify() {
        try? modelContext.save()
        SharedStore.notifyWidgets()
    }
}

// MARK: - HabitType conveniences

extension HabitType {
    /// Whether the card should render an inline progress readout beneath the title.
    var isCheckIn: Bool {
        if case .checkIn = self { return true }
        return false
    }

    /// True for `numeric` and `duration` — types that accumulate partial progress.
    var showsInlineProgress: Bool {
        switch self {
        case .checkIn: return false
        case .numeric, .duration: return true
        }
    }
}

// MARK: - Conditional long-press modifier

/// Applies the press-and-hold completion gesture only for check-in habits.
/// Numeric and duration habits complete via their inline controls, so the
/// long-press is conditionally disabled to avoid swallowing pill/timer taps.
private struct CompletionLongPressModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var isPressing: Bool
    let onComplete: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onLongPressGesture(minimumDuration: 0.4) {
                    onComplete()
                } onPressingChanged: { pressing in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPressing = pressing
                    }
                }
        } else {
            content
        }
    }
}
