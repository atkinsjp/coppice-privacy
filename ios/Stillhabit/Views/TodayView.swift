//
//  TodayView.swift
//  Stillhabit
//
//  The single, focused screen of the app.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreViewModel.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.createdAt)
    private var allHabits: [Habit]

    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.createdAt)
    private var restingHabits: [Habit]

    /// Only habits scheduled for today appear in the Today list. Cadence rules
    /// (`.daily`, `.specificDays`, `.weeklyTarget`) are evaluated client-side
    /// because SwiftData `#Predicate` can't call custom enum logic.
    private var scheduledHabits: [Habit] {
        allHabits.filter { $0.isScheduledForToday }
    }

    /// The visible habit list, ordered by the current sort mode. `.manual`
    /// uses the persisted `order` property; the completion modes sort by
    /// today's completion state (with `order` as a stable tiebreaker).
    private var habits: [Habit] {
        switch sortMode {
        case .manual:
            return scheduledHabits.sorted { $0.order < $1.order }
        case .incompleteFirst:
            return scheduledHabits.sorted { a, b in
                let aDone = a.isCompleted(on: Date()) || a.weeklyTargetMet
                let bDone = b.isCompleted(on: Date()) || b.weeklyTargetMet
                if aDone == bDone { return a.order < b.order }
                return !aDone && bDone
            }
        case .completeFirst:
            return scheduledHabits.sorted { a, b in
                let aDone = a.isCompleted(on: Date()) || a.weeklyTargetMet
                let bDone = b.isCompleted(on: Date()) || b.weeklyTargetMet
                if aDone == bDone { return a.order < b.order }
                return aDone && !bDone
            }
        }
    }

    @State private var isAddingHabit = false
    @State private var isShowingResting = false
    @State private var isShowingPaywall = false
    @State private var isShowingAmbientSettings = false
    @State private var isShowingWeeklyGraph = false
    @State private var selectedHabit: Habit?
    @State private var ambientPlayer = AmbientSoundPlayer()
    /// Current sort mode for the Today list. Persists across launches.
    @AppStorage("stillhabit.sortMode") private var sortModeRaw: String = HabitSortMode.manual.rawValue
    /// The sort mode resolved from the persisted raw value.
    private var sortMode: HabitSortMode {
        HabitSortMode(rawValue: sortModeRaw) ?? .manual
    }

    /// The "Still Moment" audio + visual reward. Plays once when the day's
    /// last scheduled habit flips to complete, and again only if the user
    /// later un-completes and re-completes everything.
    @State private var stillMomentService = StillMomentService()
    /// True while the warm-glow visual celebration is on screen. Drives the
    /// animated background and the centered completion message.
    @State private var isStillMomentActive = false
    /// The previous value of `allComplete` — used to detect the rising edge
    /// (false → true) that triggers the Still Moment.
    @State private var wasAllComplete = false
    /// Cancellable task for the Still Moment celebration timer. Cancelled
    /// when the view disappears so the animation state can't be mutated
    /// after the view is torn down.
    @State private var stillMomentTask: Task<Void, Never>?

    private var completedCount: Int {
        habits.filter { $0.isCompleted(on: Date()) || $0.weeklyTargetMet }.count
    }

    private var progress: Double {
        habits.isEmpty ? 0 : Double(completedCount) / Double(habits.count)
    }

    private var allComplete: Bool {
        !habits.isEmpty && completedCount == habits.count
    }

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()
    }

    /// Per-day overall completion ratio for the trailing 7 days, oldest first
    /// (today last). Each value is `completedScheduled / scheduled` across all
    /// non-archived habits for that calendar day. Days with no scheduled habits
    /// default to 0 so the dot stays faint — a quiet visual rest day.
    private var weekCompletionRatios: [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            let scheduled = allHabits.filter { $0.isScheduled(on: day) }
            guard !scheduled.isEmpty else { return 0 }
            let done = scheduled.filter { $0.isCompleted(on: day) }.count
            return Double(done) / Double(scheduled.count)
        }
    }

    /// Short single-letter weekday initials for the trailing 7 days, oldest
    /// first (today last). Uses the locale's very short weekday symbols.
    private var weekDayInitials: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return "" }
            let index = calendar.component(.weekday, from: day) - 1
            return symbols[index]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if habits.isEmpty {
                    emptyState
                } else {
                    progressSection

                    LazyVStack(spacing: DesignSystem.Layout.rowSpacing) {
                        ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                            HabitRowView(
                                habit: habit,
                                showsWeeklyProgress: true,
                                allowsDragReorder: sortMode == .manual,
                                listIndex: index,
                                onOpen: {
                                    selectedHabit = habit
                                },
                                onRest: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        habit.isArchived = true
                                    }
                                    SharedStore.notifyWidgets()
                                },
                                onDelete: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        modelContext.delete(habit)
                                    }
                                    SharedStore.notifyWidgets()
                                },
                                onReorder: { fromIndex, toIndex in
                                    reorderHabits(from: fromIndex, to: toIndex)
                                }
                            )
                            .opacity(isStillMomentActive ? 0 : 1)
                        }
                    }
                }

                if !restingHabits.isEmpty {
                    restingLink
                }
            }
            .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
            .padding(.top, 18)
            .padding(.bottom, 96)
        }
        .scrollDisabled(isStillMomentActive)
        .background {
            WavyBackgroundView(warmGlow: isStillMomentActive)
                .allowsHitTesting(false)
        }
        .overlay {
            if isStillMomentActive {
                stillMomentMessage
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: allComplete)
        .animation(.easeInOut(duration: 0.8), value: isStillMomentActive)
        .sheet(isPresented: $isAddingHabit) {
            AddHabitView()
        }
        .sheet(isPresented: $isShowingResting) {
            RestingHabitsView()
        }
        .sheet(item: $selectedHabit) { habit in
            HabitDetailView(habit: habit)
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $isShowingWeeklyGraph) {
            WeeklyGraphView()
        }
        .onAppear {
            ambientPlayer.startIfEnabled()
            wasAllComplete = allComplete
        }
        .onDisappear {
            stillMomentTask?.cancel()
        }
        .onChange(of: allComplete) { oldValue, newValue in
            guard !oldValue, newValue else { return }
            triggerStillMoment()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                ambientPlayer.resume()
            case .background, .inactive:
                ambientPlayer.pause()
            @unknown default:
                break
            }
        }
    }

    /// Opens the add sheet, or the paywall when the free limit is reached.
    private func requestNewHabit() {
        if !store.isPremium && habits.count >= StoreViewModel.freeHabitLimit {
            isShowingPaywall = true
        } else {
            isAddingHabit = true
        }
    }

    // MARK: - Header

    /// An elevated, branded header: the StillHabit emblem on the leading
    /// edge, the app name + tagline stacked beside it, and two clean
    /// trailing controls — a primary "+" button and a single options menu
    /// that gathers sort, analytics, and ambient sound. Generous top
    /// padding keeps the crest breathable.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dateLine)
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(alignment: .center, spacing: 12) {
                // Leading brand block — logo + stacked title/subtitle.
                HStack(alignment: .center, spacing: 12) {
                    StillHabitLogoView(size: 48)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("StillHabit")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text("Calm Habit Tracker")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.slateBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .layoutPriority(1)

                Spacer()

                // Trailing action buttons — a primary "+" and a single
                // options menu that consolidates sort, analytics, and ambient.
                HStack(spacing: 8) {
                    optionsMenu

                    Button {
                        requestNewHabit()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(DesignSystem.Colors.card, in: Circle())
                            .softShadow()
                    }
                    .frame(width: 36, height: 36)
                    .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.sage))
                    .accessibilityLabel("New habit")
                }
            }

            weekDotCalendar
        }
    }

    // MARK: - 7-day dot calendar

    /// A small, calm row of 7 dots — one per trailing day, oldest first (today
    /// last). Each dot fills proportionally to that day's overall completion
    /// ratio across all scheduled habits, so a glance reveals the week's
    /// rhythm of consistency. Today's dot carries a thin sage ring so the
    /// current day is quietly anchored. Empty days (no scheduled habits) sit as
    /// faint hollow dots, a visual rest rather than a gap.
    private var weekDotCalendar: some View {
        let ratios = weekCompletionRatios
        let initials = weekDayInitials
        let todayIndex = ratios.count - 1

        return HStack(spacing: 10) {
            ForEach(Array(ratios.enumerated()), id: \.offset) { index, ratio in
                VStack(spacing: 5) {
                    Text(initials[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            index == todayIndex
                                ? DesignSystem.Colors.sage
                                : DesignSystem.Colors.textSecondary.opacity(0.7)
                        )

                    ZStack {
                        if ratio >= 1 {
                            Circle()
                                .fill(DesignSystem.Colors.sage)
                                .frame(width: 14, height: 14)
                        } else if ratio > 0 {
                            Circle()
                                .fill(DesignSystem.Colors.softOchre.opacity(0.25 + ratio * 0.6))
                                .frame(width: 14, height: 14)
                        } else {
                            Circle()
                                .stroke(DesignSystem.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                                .frame(width: 14, height: 14)
                        }

                        if index == todayIndex {
                            Circle()
                                .stroke(DesignSystem.Colors.sage.opacity(0.8), lineWidth: 1.5)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .frame(height: 18)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.85).delay(Double(index) * 0.03),
                        value: ratios
                    )
                }
                .accessibilityElement()
                .accessibilityLabel(dotAccessibilityLabel(index: index, ratio: ratio, initials: initials))
            }
        }
        .padding(.top, 2)
    }

    /// VoiceOver label for a single day dot in the 7-day calendar.
    private func dotAccessibilityLabel(index: Int, ratio: Double, initials: [String]) -> String {
        let dayName = initials[index]
        if ratio >= 1 { return "\(dayName) — all habits complete" }
        if ratio > 0 {
            let pct = Int(ratio * 100)
            return "\(dayName) — \(pct) percent complete"
        }
        return "\(dayName) — no completions"
    }

    // MARK: - Options menu

    /// A single trailing menu button (`ellipsis`) that consolidates the
    /// secondary actions: sort order, analytics & streaks, and ambient
    /// sound mute/unmute. The primary "+" button stays standalone so the
    /// most common action remains a single tap.
    private var optionsMenu: some View {
        Menu {
            Picker("Sort habits", selection: Binding(
                get: { sortMode },
                set: { newMode in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        sortModeRaw = newMode.rawValue
                    }
                }
            )) {
                ForEach(HabitSortMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }

            Button {
                isShowingWeeklyGraph = true
            } label: {
                Label("Analytics & Streaks", systemImage: "chart.bar")
            }

            Button {
                ambientPlayer.toggleMuted()
            } label: {
                Label(
                    ambientPlayer.isMuted ? "Unmute Ambient Sounds" : "Mute Ambient Sounds",
                    systemImage: ambientPlayer.isMuted ? "speaker.slash" : "speaker.wave.2"
                )
            }

            Button {
                isShowingAmbientSettings = true
            } label: {
                Label("Ambient Sound Settings…", systemImage: "speaker.wave.1")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 36, height: 36)
                .background(DesignSystem.Colors.card, in: Circle())
                .softShadow()
        }
        .frame(width: 36, height: 36)
        .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.sage))
        .accessibilityLabel("Options")
        .accessibilityHint("Sort habits, view analytics, or toggle ambient sounds")
        .popover(isPresented: $isShowingAmbientSettings) {
            AmbientSettingsView(player: ambientPlayer)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Reorder

    /// Reorders the manually-ordered habit list by rewriting the persisted
    /// `order` values of all scheduled habits so they match the new visual
    /// sequence. Indices refer to positions in the `habits` array (already
    /// filtered to today's scheduled habits and sorted by `order`).
    private func reorderHabits(from: Int, to: Int) {
        var ordered = scheduledHabits.sorted { $0.order < $1.order }
        guard from >= 0, from < ordered.count, to >= 0, to < ordered.count else { return }
        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: to)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            for (index, habit) in ordered.enumerated() {
                habit.order = index
            }
        }
        try? modelContext.save()
        SharedStore.notifyWidgets()
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("\(completedCount) of \(habits.count)")
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(completedCount == habits.count ? "— a quiet day, well kept" : "complete")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.Colors.textSecondary.opacity(0.15))
                    Capsule()
                        .fill(DesignSystem.Colors.sage)
                        .frame(width: max(geo.size.width * progress, progress > 0 ? 4 : 0))
                }
            }
            .frame(height: 4)
            .animation(.spring(response: 0.5, dampingFraction: 0.9), value: progress)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignSystem.Colors.sage)

            Text("A quiet place for daily rituals")
                .font(DesignSystem.Typography.sectionHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Small things, done gently, every day.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Button {
                requestNewHabit()
            } label: {
                Text("Begin your first habit")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.onAccent)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .background(DesignSystem.Colors.sage, in: Capsule())
                    .softShadow()
            }
            .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.sage))
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    // MARK: - Still Moment

    /// Fires the full "Still Moment" reward the instant the day crosses from
    /// incomplete to 100% complete: a soft singing-bowl chime, a warm
    /// golden/ochre glow blooming outward across the background, a calm
    /// double-tap heartbeat haptic, and the centered completion message.
    /// The celebration resolves itself after ~4 seconds — the chime and glow
    /// fade on their own, and the message and cards return as the visual
    /// settles back to the resting earthy state.
    private func triggerStillMoment() {
        stillMomentService.playChime()
        playHeartbeatHaptic()
        withAnimation(.easeInOut(duration: 0.8)) {
            isStillMomentActive = true
        }
        stillMomentTask?.cancel()
        stillMomentTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.2)) {
                isStillMomentActive = false
            }
        }
    }

    /// A soft, low-frequency heartbeat: two slow `.soft` impacts spaced ~0.25s
    /// apart, mimicking the physical calm of a deep heartbeat rather than a
    /// jarring notification buzz.
    private func playHeartbeatHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        Task { [generator] in
            try? await Task.sleep(for: .milliseconds(250))
            generator.impactOccurred(intensity: 0.6)
        }
    }

    /// The centered, reflective completion message that fades in over the
    /// background glow once the day's rituals are all done.
    private var stillMomentMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color(hex: "D8B08C"))

            Text("Everything is still.\nYour daily rituals are complete.")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Resting link

    private var restingLink: some View {
        Button {
            isShowingResting = true
        } label: {
            Text("Resting · \(restingHabits.count)")
                .font(DesignSystem.Typography.smallNumber)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.textSecondary))
        .padding(.top, 4)
    }
}

#Preview {
    TodayView()
        .modelContainer(for: Habit.self, inMemory: true)
        .environment(StoreViewModel())
}

// MARK: - Sort mode

/// How the Today list is ordered. `.manual` honors the user's drag-to-reorder
/// arrangement (persisted via `Habit.order`); the completion modes sort by
/// today's completion state with `order` as a stable tiebreaker so habits
/// never jump around unpredictably within the same completion group.
enum HabitSortMode: String, CaseIterable, Identifiable {
    case manual
    case incompleteFirst
    case completeFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:           return "Manual"
        case .incompleteFirst:  return "Incomplete first"
        case .completeFirst:    return "Completed first"
        }
    }

    var icon: String {
        switch self {
        case .manual:           return "arrow.up.arrow.down"
        case .incompleteFirst:  return "circle"
        case .completeFirst:    return "checkmark.circle"
        }
    }
}
