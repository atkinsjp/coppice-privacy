//
//  HabitRowView.swift
//  CoppiceHabitsThatRest
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

struct HabitRowView: View {
    let habit: Habit
    /// When true (Today list), `.weeklyTarget` habits render a quiet
    /// "x of y this week" sub-label and gently fade once the target is met.
    var showsWeeklyProgress: Bool = false
    /// When true, a drag handle appears on the card and the user can
    /// press-and-drag vertically to reorder the habit in the list. Only
    /// enabled when the sort mode is `.manual`.
    var allowsDragReorder: Bool = false
    /// The habit's index in the sorted Today list, used to compute reorder
    /// positions during a drag.
    var listIndex: Int = 0
    var onOpen: () -> Void = {}
    var onRest: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Called when the user finishes a drag-to-reorder gesture. `from` is the
    /// habit's original index; `to` is the target index in the sorted list.
    var onReorder: (_ from: Int, _ to: Int) -> Void = { _, _ in }

    @Environment(\.modelContext) private var modelContext

    @State private var dragOffset: CGFloat = 0
    @State private var isPressing = false
    @State private var isRevealed = false
    @State private var waveTick = 0

    // Streak pulse state. The flame badge springs whenever the habit's
    // streak count increases after a completion — a tiny celebratory pop.
    @State private var streakPulse = false
    @State private var lastSeenStreak = 0

    // Drag-to-reorder state.
    /// Vertical offset applied to the card while it's being dragged to
    /// reorder. Reset to 0 on drop.
    @State private var reorderOffset: CGFloat = 0
    /// True while the card is lifted off the list and being dragged.
    @State private var isReordering = false
    /// The card's index at the moment the drag began, captured so the
    /// `onReorder` callback always uses the original position even if the
    /// view re-renders mid-drag.
    @State private var reorderStartIndex: Int = 0
    /// Estimated height of one row (card + spacing) used to convert the
    /// drag translation into a target index.
    private let reorderRowHeight: CGFloat = 94

    // Inline edit state (swipe-left → Edit). Scratch fields are seeded from
    // the habit on enter and committed on save. `completedDates` and `logs`
    // are never touched — only `title` and `type` may change.
    @State private var isEditing = false
    @State private var editingTitle: String = ""
    @State private var editingNumericTarget: Double = 8
    @State private var editingNumericUnit: String = ""
    @State private var editingDurationMinutes: Int = 20
    @FocusState private var isEditFieldFocused: Bool

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
    private var isTimerRunning: Bool { habit.isAlive && habit.timerStart != nil }

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
    /// Width of the hidden trailing action area. Grew from 112 to 168 when
    /// the Edit action joined Rest and Delete behind the swipe-left gesture,
    /// then to 184 to fit the labeled icon-and-caption buttons.
    private let actionsWidth: CGFloat = 184

    private var accent: Color { DesignSystem.habitColor(forHex: habit.colorHex) }

    /// The text-safe variant of the habit's accent — darkened in light mode so
    /// glyph-bearing controls (quick-add pills, play/pause) stay legible on
    /// the pale card while fills and tints keep the pastel character.
    private var accentText: Color { DesignSystem.habitTextColor(forHex: habit.colorHex) }
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

    /// The soft per-habit completion chime — a gentle two-note whisper that
    /// plays the instant any habit flips to complete. Uses the same
    /// crash-safe PCM + AudioServicesPlaySystemSound approach as the Still
    /// Moment service (no AVFoundation, no audio session) so it can never
    /// trigger the simulator audio-session abort.
    private let completionSound = CompletionSoundService.shared

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

    /// The streak count with a unit suffix appropriate to the cadence —
    /// "d" for daily/specific-days habits, "w" for weekly-target habits
    /// whose streak counts consecutive target-metting weeks.
    ///
    /// Takes the streak as a parameter rather than reading `habit.currentStreak`
    /// itself: that property walks backwards through the calendar one day at a
    /// time, and the card used to recompute it three separate times on every
    /// single body evaluation — during drags, ripples, and timer ticks that is
    /// hundreds of `Calendar` round-trips a second on the main thread.
    private func streakLabel(_ streak: Int) -> String? {
        guard streak > 0 else { return nil }
        if case .weeklyTarget = habit.cadence {
            return "\(streak)w"
        }
        return "\(streak)d"
    }

    /// Whether the streak is long enough to warrant a slightly warmer, more
    /// prominent flame — 7+ for day streaks, 2+ for week streaks (since
    /// weekly streaks are harder to sustain).
    private func isLongStreak(_ streak: Int) -> Bool {
        guard streak > 0 else { return false }
        if case .weeklyTarget = habit.cadence {
            return streak >= 2
        }
        return streak >= 7
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
            // A deleted habit is kept on screen by SwiftUI for the length of
            // its removal transition. Reading any property of it in that
            // window raises NSObjectInaccessibleException and aborts, so the
            // card collapses to nothing the moment the model goes away.
            if habit.isAlive {
                swipeHint
                if isEditing {
                    inlineEditor
                } else {
                    card
                }
                // The action chips render ABOVE the card. When they sat
                // underneath, the offset card's tap region could still shadow
                // them on device — every chip tap landed on the card and
                // silently closed the reveal. Topmost + hit-testing gated on
                // the reveal keeps them untouchable while hidden and
                // unshadowable while shown.
                quickActions
            }
        }
        .onAppear {
            guard habit.isAlive else { return }
            seedTimerDisplay()
            lastSeenStreak = habit.currentStreak
        }
        // The countdown only needs a heartbeat while a focus timer is actually
        // running. The previous `.onReceive(Timer.publish(...))` built a brand
        // new run-loop timer on *every* body evaluation and kept every card
        // ticking five times a second for the whole session, whether or not it
        // had a timer — a permanent CPU tax that grew with the list. `.task(id:)`
        // starts one loop when the timer starts and tears it down when it stops.
        .task(id: isTimerRunning) {
            guard isTimerRunning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, habit.isAlive, habit.timerStart != nil else { return }
                tickTimer()
            }
        }
    }

    // MARK: - Card

    /// The inner card content, extracted so the outer HStack type-checks
    /// quickly instead of trying to resolve the whole nested builder at once.
    private var cardBody: some View {
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
    }

    private var card: some View {
        cardAccessibility
    }

    /// The layout stack: optional drag handle beside the card body.
    private var cardStack: some View {
        HStack(spacing: 0) {
            if allowsDragReorder, !isEditing {
                dragHandle
                    .padding(.leading, 8)
            }

            cardBody
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Fill, streak badge, border pulse, and the rounded card surface.
    private var cardSurface: some View {
        let streak = habit.isAlive ? habit.currentStreak : 0
        return cardStack
            .overlay(alignment: .topTrailing) {
                if let label = streakLabel(streak) {
                    streakBadge(label, isLong: isLongStreak(streak))
                }
            }
            .background(cardBackground)
            .overlay { borderPulseOverlay }
            .clipShape(.rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            .softShadow()
            .tactileWave(accent: accent, trigger: waveTick)
    }

    /// Press and drag-reorder transforms, plus the completed-card dim.
    private var cardMotion: some View {
        cardSurface
            .scaleEffect(isReordering ? 1.03 : (isPressing ? 0.97 : 1))
            .offset(x: currentOffset)
            .offset(y: reorderOffset)
            .zIndex(isReordering ? 100 : 0)
            .shadow(color: isReordering ? Color.black.opacity(0.12) : .clear, radius: isReordering ? 20 : 0)
            // Completed cards gently dim so incomplete habits stay the visual focus.
            // The accent fill remains, but the whole card recedes to ~58% opacity —
            // enough to signal "done, move on" without hiding the streak or checkmark.
            .opacity(isEffectivelyDone ? 0.58 : 1)
    }

    private var cardAnimated: some View {
        cardMotion
            .animation(cardSpring, value: isEffectivelyDone)
            .animation(cardSpring, value: isTimerExpanded)
            .animation(cardSpring, value: habit.todayProgress)
            .animation(.easeInOut(duration: 0.4), value: isWhyRevealed)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isReordering)
    }

    private var cardInteractive: some View {
        cardAnimated
            .contentShape(.rect)
            .onTapGesture { handleCardTap() }
            .modifier(CompletionLongPressModifier(
                isEnabled: habitType.isCheckIn && !isEditing && !isReordering,
                isPressing: $isPressing,
                onComplete: { toggle() }
            ))
            .simultaneousGesture(drag)
    }

    private var cardAccessibility: some View {
        let streak = habit.isAlive ? habit.currentStreak : 0
        return cardInteractive
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(habit.title)
            .accessibilityValue(accessibilityValueText(streak: streak))
            .accessibilityAction(named: "Open details") { onOpen() }
            .accessibilityAction(named: isDoneToday ? "Mark incomplete" : "Mark complete") { toggle() }
            .accessibilityAction(named: "Edit name and goal") { beginEditing() }
            .accessibilityAction(named: "Let it rest") { onRest() }
            .accessibilityAction(named: "Delete") { onDelete() }
            .accessibilityAction(named: "Move up") { onReorder(listIndex, max(0, listIndex - 1)) }
            .accessibilityAction(named: "Move down") { onReorder(listIndex, listIndex + 1) }
    }

    private func handleCardTap() {
        if isRevealed {
            withAnimation(cardSpring) { isRevealed = false }
        } else if !isReordering {
            waveTick += 1
            onOpen()
        }
    }

    // MARK: - Streak badge

    /// A small, warm flame + count badge shown in the card's top-trailing
    /// corner. The flame icon gives an immediate visual hook for motivation
    /// while staying quiet — terracotta on rest, softened on-accent when done.
    /// Longer streaks get a slightly fuller flame symbol as a gentle reward.
    private func streakBadge(_ label: String, isLong: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isLong ? "flame.fill" : "flame")
                .font(.system(size: 10, weight: .medium))
            Text(label)
                .font(DesignSystem.Typography.smallNumber)
                .monospacedDigit()
        }
        .foregroundStyle(
            isEffectivelyDone
                ? DesignSystem.Colors.onAccent.opacity(0.72)
                : isLong
                    ? DesignSystem.Colors.terracotta
                    : DesignSystem.Colors.softOchre
        )
        .scaleEffect(streakPulse ? 1.35 : 1)
        .padding(.top, 12)
        .padding(.trailing, 16)
        .accessibilityHidden(true)
    }

    /// Fires a one-shot spring pop on the flame badge when the streak has
    /// grown since the last observed value. Called after every completion
    /// path (toggle, quick-add, timer). Does nothing when the streak is
    /// unchanged or broken — only an increase earns the pop.
    private func fireStreakPulseIfNeeded() {
        guard habit.isAlive else { return }
        let streak = habit.currentStreak
        guard streak > lastSeenStreak else {
            lastSeenStreak = streak
            return
        }
        lastSeenStreak = streak
        streakPulse = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) {
            streakPulse = false
        }
    }

    // MARK: - Drag handle (reorder)

    /// A subtle grip icon shown on the leading edge of the card when manual
    /// reordering is enabled. Pressing and dragging vertically on the handle
    /// lifts the card out of the stack and repositions it in the list.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
            .frame(width: 20)
            .contentShape(.rect)
            .gesture(reorderDrag)
            .accessibilityHidden(true)
    }

    /// The vertical drag gesture attached to the reorder handle. On change,
    /// applies the translation as a vertical offset and lifts the card. On
    /// end, computes the target index from the total translation divided by
    /// the estimated row height and calls `onReorder`.
    private var reorderDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !isReordering {
                    reorderStartIndex = listIndex
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isReordering = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                reorderOffset = value.translation.height
            }
            .onEnded { value in
                let rowDelta = Int((value.translation.height / reorderRowHeight).rounded())
                let targetIndex = max(0, reorderStartIndex + rowDelta)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    reorderOffset = 0
                    isReordering = false
                }
                if targetIndex != reorderStartIndex {
                    onReorder(reorderStartIndex, targetIndex)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    private func accessibilityValueText(streak: Int) -> String {
        let base = isEffectivelyDone
            ? "Completed today\(lastCompletionLabel.map { ", \($0)" } ?? "")"
            : "Not completed today\(lastCompletionLabel.map { ", last done \($0)" } ?? "")"
        let streakSuffix: String = {
            guard streak > 0 else { return "" }
            if case .weeklyTarget = habit.cadence {
                return ", \(streak) week streak"
            }
            return ", \(streak) day streak"
        }()
        let fullBase = base + streakSuffix
        switch habitType {
        case .checkIn:
            return fullBase
        case .numeric:
            return "\(fullBase), \(habit.todayProgressLabel)"
        case .duration:
            return "\(fullBase), \(habit.todayProgressLabel)"
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
                        .foregroundStyle(isEffectivelyDone ? DesignSystem.Colors.onAccent : accentText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            Group {
                                if isEffectivelyDone {
                                    Capsule().fill(DesignSystem.Colors.onAccent.opacity(0.18))
                                } else {
                                    // 0.26 (not 0.14): the pastel palette at 14% over
                                    // the near-white card reads as white for every
                                    // color — the pill must visibly carry the habit's
                                    // chosen accent.
                                    Capsule().fill(accent.opacity(0.26))
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
        guard habit.isAlive else { return }
        let wasDone = isEffectivelyDone
        habit.logProgress(value, on: Date())
        if !wasDone, isEffectivelyDone {
            waveTick += 1
            completionSound.playChime()
            fireStreakPulseIfNeeded()
        } else {
            lastSeenStreak = habit.currentStreak
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
                .foregroundStyle(isEffectivelyDone ? DesignSystem.Colors.onAccent : accentText)
                .frame(width: 40, height: 40)
                .background(
                    Group {
                        if isEffectivelyDone {
                            Circle().fill(DesignSystem.Colors.onAccent.opacity(0.18))
                        } else {
                            // Same as the pills: 14% vanished on the pale card.
                            Circle().fill(accent.opacity(0.26))
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
        guard habit.isAlive, !isEffectivelyDone else { return }
        CrashDiagnostics.note("timer start")
        withAnimation(cardSpring) { isTimerExpanded = true }
        habit.timerStart = Date()
        saveAndNotify()
        startBorderPulse()
    }

    /// Pauses the timer: commits the elapsed seconds since `timerStart` to the
    /// habit's `logs`, clears the persisted anchor, and persists so progress
    /// survives across card interactions and app launches.
    private func pauseTimer() {
        guard habit.isAlive, let start = habit.timerStart else { return }
        CrashDiagnostics.note("timer pause")
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
        guard habit.isAlive, let start = habit.timerStart else { return }
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
        guard habit.isAlive, let start = habit.timerStart else { return }
        CrashDiagnostics.note("timer complete")
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
        completionSound.playChime()
        fireStreakPulseIfNeeded()
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
        guard habit.isAlive, case .duration = habitType else { return }
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
                    accent.opacity(0.28)
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var hintProgress: CGFloat {
        min(max(currentOffset / completionThreshold, 0), 1)
    }

    // MARK: - Hidden quiet actions

    /// The revealed edit / rest / delete controls. Each is an explicitly
    /// labeled chip — icon over a short word — so it visibly reads as a
    /// tappable control rather than a floating glyph. Bare icons at the
    /// screen edge read as decorative, which made the actions feel inert.
    private var quickActions: some View {
        HStack(spacing: 10) {
            Spacer()

            quickActionButton(
                icon: "pencil",
                title: "Edit",
                tint: DesignSystem.Colors.slateBlue
            ) {
                withAnimation(cardSpring) { isRevealed = false }
                beginEditing()
            }

            quickActionButton(
                icon: "moon.zzz",
                title: "Rest",
                tint: DesignSystem.Colors.textSecondary
            ) {
                withAnimation(cardSpring) { isRevealed = false }
                onRest()
            }

            quickActionButton(
                icon: "trash",
                title: "Delete",
                tint: DesignSystem.Colors.terracotta
            ) {
                withAnimation(cardSpring) { isRevealed = false }
                onDelete()
            }
        }
        .padding(.trailing, 6)
        .opacity(currentOffset < -12 ? 1 : 0)
        .allowsHitTesting(currentOffset < -12)
        .animation(cardSpring, value: isRevealed)
    }

    /// One labeled action chip: a soft tinted tile with the icon and its
    /// word beneath, comfortably above the 44pt minimum target.
    private func quickActionButton(
        icon: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 18)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(width: 50, height: 56)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.stillTactileWave(accent: tint))
        .accessibilityLabel("\(title) \(habit.title)")
    }

    // MARK: - Inline editor (swipe-to-edit)

    /// The inline edit surface shown in place of the card after tapping the
    /// Edit action revealed by swiping left. Lets the user adjust the habit's
    /// name and its goal (numeric target/unit or duration minutes) without
    /// opening the detail view. Only `title` and `type` are written back on
    /// save — `completedDates`, `logs`, cadence, color, and `whyString` are
    /// all preserved untouched.
    private var inlineEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Habit name", text: $editingTitle)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(14)
                .background(DesignSystem.Colors.background, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                .focused($isEditFieldFocused)
                .submitLabel(.done)
                .onSubmit { commitEdit() }

            editGoalField

            HStack(spacing: 12) {
                Spacer()
                Button {
                    cancelEdit()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(height: 40)
                        .padding(.horizontal, 20)
                        .background(DesignSystem.Colors.background, in: Capsule())
                }
                .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.textSecondary))
                .accessibilityLabel("Cancel edit")

                Button {
                    commitEdit()
                } label: {
                    Text("Save")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.onAccent)
                        .frame(height: 40)
                        .padding(.horizontal, 24)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.stillTactileWave(accent: accent))
                .disabled(trimmedEditingTitle.isEmpty)
                .opacity(trimmedEditingTitle.isEmpty ? 0.4 : 1)
                .accessibilityLabel("Save changes")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.card)
        .clipShape(.rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .softShadow()
        .scaleEffect(isPressing ? 0.97 : 1)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(cardSpring, value: isEditing)
        .onAppear {
            isEditFieldFocused = true
        }
        .accessibilityElement(children: .contain)
    }

    /// Type-aware goal editor shown beneath the title field. Check-in habits
    /// have nothing to adjust, so only a quiet hint is shown.
    @ViewBuilder
    private var editGoalField: some View {
        switch habitType {
        case .checkIn:
            Text("Check-in habits have no numeric goal to edit.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        case .numeric:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TARGET")
                        .font(DesignSystem.Typography.overline)
                        .tracking(1.2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    TextField("8", text: editingTargetText)
                        .keyboardType(.decimalPad)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(12)
                        .background(DesignSystem.Colors.background, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("UNIT")
                        .font(DesignSystem.Typography.overline)
                        .tracking(1.2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    TextField("glasses, oz…", text: $editingNumericUnit)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(12)
                        .background(DesignSystem.Colors.background, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                }
            }
        case .duration:
            HStack(spacing: 14) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        editingDurationMinutes = max(1, editingDurationMinutes - 5)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.background, in: Circle())
                }
                .buttonStyle(.stillTactileWave(accent: accent))
                .disabled(editingDurationMinutes <= 5)
                .accessibilityLabel("Decrease focus length")

                Text("\(editingDurationMinutes)\u{2009}minutes")
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .frame(maxWidth: .infinity)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        editingDurationMinutes = min(120, editingDurationMinutes + 5)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.background, in: Circle())
                }
                .buttonStyle(.stillTactileWave(accent: accent))
                .disabled(editingDurationMinutes >= 120)
                .accessibilityLabel("Increase focus length")
            }
        }
    }

    /// Lightweight binding that parses the numeric target field and clamps it
    /// to a positive value.
    private var editingTargetText: Binding<String> {
        Binding(
            get: { ValueFormatter.wholeOrDecimal(editingNumericTarget) },
            set: { newValue in
                let parsed = Double(newValue.replacingOccurrences(of: ",", with: "."))
                if let parsed, parsed > 0 {
                    editingNumericTarget = parsed
                }
            }
        )
    }

    /// The trimmed editing title, used to gate the Save button.
    private var trimmedEditingTitle: String {
        editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Seeds the scratch fields from the habit and flips into edit mode.
    private func beginEditing() {
        guard habit.isAlive else { return }
        editingTitle = habit.title
        switch habitType {
        case .checkIn:
            break
        case .numeric(let target, let unit):
            editingNumericTarget = max(1, target)
            editingNumericUnit = unit
        case .duration(let minutes):
            editingDurationMinutes = max(1, minutes)
        }
        withAnimation(cardSpring) {
            isEditing = true
        }
    }

    /// Writes the trimmed title and resolved type back to the habit without
    /// touching `completedDates` or `logs`, then exits edit mode.
    private func commitEdit() {
        let trimmed = trimmedEditingTitle
        guard habit.isAlive, !trimmed.isEmpty else { return }
        habit.title = trimmed
        switch habitType {
        case .checkIn:
            break
        case .numeric:
            let cleanedUnit = editingNumericUnit.trimmingCharacters(in: .whitespaces)
            habit.type = .numeric(
                target: max(1, editingNumericTarget),
                unit: cleanedUnit.isEmpty ? "units" : cleanedUnit
            )
        case .duration:
            habit.type = .duration(targetMinutes: max(1, min(120, editingDurationMinutes)))
        }
        saveAndNotify()
        withAnimation(cardSpring) {
            isEditing = false
        }
        isEditFieldFocused = false
    }

    /// Discards the scratch fields and exits edit mode without any writes.
    private func cancelEdit() {
        withAnimation(cardSpring) {
            isEditing = false
        }
        isEditFieldFocused = false
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
                    // First successful reveal retires the Today-list hint.
                    UserDefaults.standard.set(true, forKey: HintFlags.learnedSwipeActions)
                }
                withAnimation(cardSpring) { dragOffset = 0 }
            }
    }

    // MARK: - Actions

    /// Flips today's completion. The tactile wave modifier fires the medium
    /// haptic pulse and the outward ripple the instant `waveTick` changes.
    /// Disabled while the inline editor is open so the long-press can't fire
    /// underneath the text fields.
    private func toggle() {
        guard habit.isAlive, !isEditing else { return }
        CrashDiagnostics.note("toggle habit")
        let willComplete = !isDoneToday
        waveTick += 1
        withAnimation(cardSpring) {
            habit.toggleCompletion(on: Date())
        }
        if willComplete {
            completionSound.playChime()
            fireStreakPulseIfNeeded()
        } else {
            lastSeenStreak = habit.currentStreak
        }
        saveAndNotify()
    }

    /// Persists the current model state and asks widgets to refresh.
    private func saveAndNotify() {
        guard habit.isAlive else { return }
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
