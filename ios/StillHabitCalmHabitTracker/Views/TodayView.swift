//
//  TodayView.swift
//  StillHabitCalmHabitTracker
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
        // `isAlive` filters out models that were deleted but are still being
        // held by SwiftUI during their removal transition — reading their
        // properties would raise NSObjectInaccessibleException and abort.
        allHabits.filter { $0.isAlive && $0.isScheduledForToday }
    }

    /// Alive (non-deleted) habit count. Watched to detect when a brand-new
    /// habit has just been created so it can be brought into view.
    private var liveHabitCount: Int {
        allHabits.filter { $0.isAlive }.count
    }

    /// Everything the screen needs about today, derived in a single pass.
    ///
    /// Each of these used to be its own computed property, and SwiftUI reads
    /// them several times per body evaluation — the list, the completion
    /// count, the progress bar, the "all complete" trigger, and the 7-day
    /// dot row each re-scanned every habit's `completedDates` from scratch,
    /// and the completion sort modes re-derived the done flag inside the
    /// comparator on every comparison. During a drag or a ripple that runs at
    /// display rate on the main thread. One pass now feeds all of them.
    private struct TodaySnapshot {
        let habits: [Habit]
        let completedCount: Int
        let progress: Double
        let allComplete: Bool
        /// Per-day overall completion ratio for the current calendar week,
        /// oldest first (future days of the week are 0).
        let weekRatios: [Double]
    }

    private func makeSnapshot() -> TodaySnapshot {
        let calendar = Calendar.current
        let now = Date()
        // `isAlive` filters out models that were deleted but are still being
        // held by SwiftUI during their removal transition — reading their
        // properties would raise NSObjectInaccessibleException and abort.
        let live = allHabits.filter { $0.isAlive }

        let entries: [(habit: Habit, isDone: Bool)] = live
            .filter { $0.isScheduled(on: now) }
            .map { (habit: $0, isDone: $0.isCompleted(on: now) || $0.weeklyTargetMet) }

        let sorted: [(habit: Habit, isDone: Bool)]
        switch sortMode {
        case .manual:
            sorted = entries.sorted { $0.habit.order < $1.habit.order }
        case .incompleteFirst:
            sorted = entries.sorted { a, b in
                a.isDone == b.isDone ? a.habit.order < b.habit.order : (!a.isDone && b.isDone)
            }
        case .completeFirst:
            sorted = entries.sorted { a, b in
                a.isDone == b.isDone ? a.habit.order < b.habit.order : (a.isDone && !b.isDone)
            }
        }

        let completedCount = sorted.reduce(into: 0) { $0 += $1.isDone ? 1 : 0 }
        let total = sorted.count

        let today = calendar.startOfDay(for: now)
        let weekRatios: [Double] = weekDates.map { day in
            // Days later in the week than today have no history yet.
            guard calendar.compare(day, to: today, toGranularity: .day) != .orderedDescending else { return 0 }
            var scheduled = 0
            var done = 0
            for habit in live where habit.isScheduled(on: day) {
                scheduled += 1
                if habit.isCompleted(on: day) { done += 1 }
            }
            guard scheduled > 0 else { return 0 }
            return Double(done) / Double(scheduled)
        }

        return TodaySnapshot(
            habits: sorted.map(\.habit),
            completedCount: completedCount,
            progress: total == 0 ? 0 : Double(completedCount) / Double(total),
            allComplete: total > 0 && completedCount == total,
            weekRatios: weekRatios
        )
    }

    /// The single presented sheet, if any.
    ///
    /// SwiftUI supports exactly **one** sheet presentation per view. Stacking
    /// several `.sheet` modifiers on the same view lets two presentations race
    /// each other — the second one lands on a view controller that is already
    /// presenting, which UIKit answers with an Objective-C exception that no
    /// Swift `do/catch` can trap and that aborts the process. Routing every
    /// destination through one modifier makes that structurally impossible.
    ///
    /// The habit detail case carries an *identifier* rather than the model
    /// itself: a `Habit` kept in view state can be deleted from underneath the
    /// sheet, and SwiftUI reads its `id` on every render while the sheet
    /// dismisses — touching a deleted SwiftData model raises
    /// `NSObjectInaccessibleException`. An identifier is inert, and the model
    /// is re-resolved from the live query on each render.
    @State private var route: TodayRoute?
    @State private var ambientPlayer = AmbientSoundPlayer()
    /// Quiet footnote shown after a habit is created that does NOT run today
    /// (a specific-days cadence) — without it the sheet closes and nothing on
    /// screen changes, which reads as if the habit never saved.
    @State private var offScheduleNote: String?
    @State private var offScheduleNoteTask: Task<Void, Never>?
    /// Current sort mode for the Today list. Persists across launches.
    @AppStorage("stillhabit.sortMode") private var sortModeRaw: String = HabitSortMode.manual.rawValue
    /// Set automatically once the user swipes a card left for the first time
    /// (written by `HabitRowView`); retires the swipe-actions hint line.
    @AppStorage(HintFlags.learnedSwipeActions) private var didLearnSwipeActions = false
    /// The sort mode resolved from the persisted raw value.
    private var sortMode: HabitSortMode {
        HabitSortMode(rawValue: sortModeRaw) ?? .manual
    }

    /// The "Still Moment" audio + visual reward. Plays once when the day's
    /// last scheduled habit flips to complete, and again only if the user
    /// later un-completes and re-completes everything.
    private let stillMomentService = StillMomentService.shared
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

    /// True while the post-purchase petal-and-ripple celebration is on
    /// screen. Triggered by `StoreViewModel.purchaseCelebrationTick`, which
    /// only moves on a genuine purchase — never on the launch-time
    /// entitlement refresh for existing subscribers.
    @State private var isProCelebrationActive = false
    /// Timer for the celebration's own lifetime, cancelled on disappear.
    @State private var proCelebrationTask: Task<Void, Never>?

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()
    }

    /// The 7 days of the current calendar week, oldest first, anchored at the
    /// locale's first weekday (Sunday in the US, Monday in most of Europe) so
    /// the strip reads in calendar order rather than as a trailing window.
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - leading, to: today)
        }
    }

    /// Short single-letter weekday initials for the current calendar week,
    /// oldest first. Uses the locale's very short weekday symbols.
    private var weekDayInitials: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        return weekDates.map { day in
            symbols[calendar.component(.weekday, from: day) - 1]
        }
    }

    var body: some View {
        let snapshot = makeSnapshot()

        // The reader lets a just-created habit scroll itself into view — past
        // ~4 cards the list fills the viewport and the new row lands below
        // the fold, which made adding feel like nothing happened.
        return ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(weekRatios: snapshot.weekRatios, habitCount: snapshot.habits.count)

                if snapshot.habits.isEmpty {
                    emptyState
                } else {
                    progressSection(completed: snapshot.completedCount, total: snapshot.habits.count, progress: snapshot.progress)

                    if !didLearnSwipeActions {
                        swipeEducationHint
                    }

                    if let offScheduleNote {
                        Text(offScheduleNote)
                            .font(.system(size: 13))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .transition(.opacity)
                    }

                    LazyVStack(spacing: DesignSystem.Layout.rowSpacing) {
                        ForEach(Array(snapshot.habits.enumerated()), id: \.element.id) { index, habit in
                            HabitRowView(
                                habit: habit,
                                showsWeeklyProgress: true,
                                allowsDragReorder: sortMode == .manual,
                                listIndex: index,
                                onOpen: {
                                    present(.detail(habit.id))
                                },
                                onRest: {
                                    rest(habit)
                                },
                                onDelete: {
                                    delete(habit)
                                },
                                onReorder: { fromIndex, toIndex in
                                    reorderHabits(from: fromIndex, to: toIndex)
                                }
                            )
                            .opacity(isStillMomentActive ? 0 : 1)
                            .id(habit.id)
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
        .animation(.easeInOut(duration: 0.35), value: didLearnSwipeActions)
        .animation(.easeInOut(duration: 0.35), value: offScheduleNote)
        .scrollDisabled(isStillMomentActive)
        .background {
            // The backdrop's drift is a render-server animation now, not a
            // per-frame redraw, so there is nothing left to pause behind a
            // sheet or while the scene is inactive.
            WavyBackgroundView(warmGlow: isStillMomentActive)
                .allowsHitTesting(false)
        }
        .overlay {
            if isStillMomentActive {
                stillMomentMessage
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            // The purchase thank-you floats over everything but blocks
            // nothing — the list stays scrollable and tappable underneath.
            if isProCelebrationActive {
                ProCelebrationView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: isProCelebrationActive)
        .animation(.easeInOut(duration: 0.8), value: snapshot.allComplete)
        .animation(.easeInOut(duration: 0.8), value: isStillMomentActive)
        .sheet(item: $route) { destination in
            sheetContent(for: destination)
        }
        .onAppear {
            ambientPlayer.startIfEnabled()
            wasAllComplete = snapshot.allComplete
        }
        .onDisappear {
            stillMomentTask?.cancel()
            proCelebrationTask?.cancel()
            offScheduleNoteTask?.cancel()
        }
        .onChange(of: snapshot.allComplete) { oldValue, newValue in
            guard !oldValue, newValue else { return }
            triggerStillMoment()
        }
        .onChange(of: store.purchaseCelebrationTick) { oldValue, newValue in
            guard newValue > oldValue else { return }
            celebratePurchase()
        }
        .onChange(of: scenePhase) { _, newPhase in
            CrashDiagnostics.note("scene phase \(newPhase)")
            switch newPhase {
            case .active:
                ambientPlayer.resume()
            case .background, .inactive:
                ambientPlayer.pause()
            @unknown default:
                break
            }
        }
        .onChange(of: liveHabitCount) { oldCount, newCount in
            guard newCount > oldCount else { return }
            handleHabitAppeared(proxy: proxy)
        }
        }
    }

    /// Brings a just-created habit into view. If it runs today, scroll to it
    /// (new habits append at the bottom of the list); if its cadence starts on
    /// a later weekday, show a quiet "starts Tuesday" note instead, since it
    /// intentionally does not appear on today's list.
    private func handleHabitAppeared(proxy: ScrollViewProxy) {
        let live = allHabits.filter { $0.isAlive }
        guard let newest = live.max(by: { $0.createdAt < $1.createdAt }) else { return }
        if newest.isScheduledForToday {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                proxy.scrollTo(newest.id, anchor: .bottom)
            }
        } else if let day = newest.nextScheduledWeekdayName {
            showOffScheduleNote("\(newest.title) starts \(day)")
        }
    }

    private func showOffScheduleNote(_ note: String) {
        offScheduleNoteTask?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) {
            offScheduleNote = note
        }
        offScheduleNoteTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                offScheduleNote = nil
            }
        }
    }

    /// Opens the add sheet, or asks the root view to raise the paywall when
    /// the free limit is reached.
    private func requestNewHabit(habitCount: Int) {
        // `hasFullAccess` is true for subscribers *and* for anyone still
        // inside the 72-hour local grace window, so a brand-new user is never
        // stopped by the paywall.
        if !store.hasFullAccess && habitCount >= StoreViewModel.freeHabitLimit {
            // The paywall is a full-screen lock owned by `ContentView`; a
            // second presentation attached to this view could race the sheet.
            guard route == nil else { return }
            store.isPaywallRequested = true
        } else {
            present(.addHabit)
        }
    }

    /// Routes to a destination, ignoring the request if something is already
    /// on screen. A menu item and a card tap can both fire within the same
    /// run loop turn; swapping the route mid-presentation is exactly the race
    /// that aborts, so the first one through wins.
    private func present(_ destination: TodayRoute) {
        guard route == nil else { return }
        CrashDiagnostics.note("present \(destination.id)")
        route = destination
    }

    /// Builds the body of whichever destination is presented.
    @ViewBuilder
    private func sheetContent(for destination: TodayRoute) -> some View {
        switch destination {
        case .addHabit:
            AddHabitView()
        case .resting:
            RestingHabitsView()
        case .detail(let habitID):
            if let habit = allHabits.first(where: { $0.isAlive && $0.id == habitID }) {
                HabitDetailView(habit: habit)
            } else {
                // Clearing the route from `onAppear` would dismiss the sheet
                // in the middle of its own presentation transaction — an
                // uncatchable UIKit exception. Wait one turn.
                Color.clear.task {
                    try? await Task.sleep(for: .milliseconds(60))
                    route = nil
                }
            }
        case .weeklyGraph:
            WeeklyGraphView()
        case .settings:
            SettingsView(player: ambientPlayer)
        }
    }

    // MARK: - Header

    /// An elevated, branded header: the StillHabit emblem on the leading
    /// edge, the app name + tagline stacked beside it, and two clean
    /// trailing controls — a primary "+" button and a single options menu
    /// that gathers sort, analytics, and ambient sound. Generous top
    /// padding keeps the crest breathable.
    private func header(weekRatios: [Double], habitCount: Int) -> some View {
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
                        Text("Coppice")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("Habits that rest and regrow")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.slateBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .layoutPriority(1)

                Spacer()

                // Trailing action buttons — a primary "+" and the utilities
                // sheet. Everything secondary (appearance, order, ambient
                // sound, subscription, support) lives behind the slider.
                HStack(spacing: 8) {
                    settingsButton

                    Button {
                        requestNewHabit(habitCount: habitCount)
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

            weekDotCalendar(ratios: weekRatios)
        }
    }

    // MARK: - 7-day dot calendar

    /// A small, calm row of 7 dots — one per day of the current calendar week,
    /// oldest first. Each dot fills proportionally to that day's overall completion
    /// ratio across all scheduled habits, so a glance reveals the week's
    /// rhythm of consistency. Today's dot carries a thin sage ring so the
    /// current day is quietly anchored. Empty days (no scheduled habits) sit as
    /// faint hollow dots, a visual rest rather than a gap.
    private func weekDotCalendar(ratios: [Double]) -> some View {
        Button {
            present(.weeklyGraph)
        } label: {
            weekDotRow(ratios: ratios)
        }
        .buttonStyle(.stillQuietPress)
        .accessibilityHint("Opens analytics and streaks")
    }

    private func weekDotRow(ratios: [Double]) -> some View {
        let initials = weekDayInitials
        let todayIndex = weekDates.firstIndex { Calendar.current.isDateInToday($0) } ?? ratios.count - 1

        return HStack(spacing: 10) {
            ForEach(Array(ratios.enumerated()), id: \.offset) { index, ratio in
                let isFuture = index > todayIndex
                VStack(spacing: 5) {
                    Text(initials[index])
                        .font(.system(size: 10, weight: index == todayIndex ? .heavy : .semibold))
                        .foregroundStyle(DesignSystem.Colors.textStrong)
                        .opacity(index == todayIndex ? 1 : (isFuture ? 0.45 : 0.9))

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
                                .stroke(
                                    DesignSystem.Colors.textSecondary.opacity(isFuture ? 0.12 : 0.2),
                                    lineWidth: 1
                                )
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
                .accessibilityLabel(dotAccessibilityLabel(index: index, ratio: ratio, initials: initials, isFuture: index > todayIndex))
            }

            Spacer(minLength: 4)

            // A quiet affordance: the week row is the way into analytics.
            Image(systemName: "chart.bar")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.top, 15)
                .accessibilityHidden(true)
        }
        .padding(.top, 2)
        .contentShape(.rect)
    }

    /// VoiceOver label for a single day dot in the 7-day calendar.
    private func dotAccessibilityLabel(index: Int, ratio: Double, initials: [String], isFuture: Bool) -> String {
        let dayName = initials[index]
        if isFuture { return "\(dayName) — upcoming" }
        if ratio >= 1 { return "\(dayName) — all habits complete" }
        if ratio > 0 {
            let pct = Int(ratio * 100)
            return "\(dayName) — \(pct) percent complete"
        }
        return "\(dayName) — no completions"
    }

    // MARK: - Settings button

    /// The utilities entry point. A plain button rather than a menu: a `Menu`
    /// that dismisses while a presentation begins is one of the races that can
    /// abort the process, and every secondary control now has a calm home
    /// inside the sheet.
    private var settingsButton: some View {
        Button {
            present(.settings)
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
        .accessibilityLabel("Settings")
        .accessibilityHint("Appearance, order, ambient sound, and subscription")
    }

    // MARK: - Swipe education

    /// A small, quiet line above the habit list teaching the left-swipe.
    /// Disappears forever the first time the user reveals a card's actions —
    /// `HabitRowView` writes the flag when the reveal springs open.
    private var swipeEducationHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.left.to.line")
                .font(.system(size: 11, weight: .medium))
            Text("Slide a habit left to edit, rest, or delete")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.75))
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .accessibilityHint("Swipe left on a habit to edit it, let it rest, or delete it")
    }

    // MARK: - Rest & delete

    /// Archives a habit and cancels its pending reminders.
    private func rest(_ habit: Habit) {
        guard habit.isAlive else { return }
        CrashDiagnostics.note("rest habit")
        dismissDetail(for: habit.id)
        ReminderService.shared.cancelReminder(habitID: habit.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            habit.isArchived = true
        }
        try? modelContext.save()
        SharedStore.notifyWidgets()
    }

    /// Permanently removes a habit. Everything that reads the model — the
    /// open detail sheet, the pending reminders — is torn down *before* the
    /// delete, and the context is saved immediately so no view is left
    /// holding a deleted object it might try to read from.
    private func delete(_ habit: Habit) {
        guard habit.isAlive else { return }
        CrashDiagnostics.note("delete habit")
        dismissDetail(for: habit.id)
        ReminderService.shared.cancelReminder(habitID: habit.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            modelContext.delete(habit)
        }
        try? modelContext.save()
        SharedStore.notifyWidgets()
    }

    /// Closes the detail sheet if it is showing the habit about to go away,
    /// so nothing is left reading a model that is being archived or deleted.
    private func dismissDetail(for habitID: UUID) {
        if case .detail(let shown) = route, shown == habitID {
            route = nil
        }
    }

    // MARK: - Reorder

    /// Reorders the manually-ordered habit list by rewriting the persisted
    /// `order` values of all scheduled habits so they match the new visual
    /// sequence. Indices refer to positions in the `habits` array (already
    /// filtered to today's scheduled habits and sorted by `order`).
    private func reorderHabits(from: Int, to: Int) {
        var ordered = scheduledHabits.sorted { $0.order < $1.order }
        guard !ordered.isEmpty else { return }
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

    private func progressSection(completed: Int, total: Int, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("\(completed) of \(total)")
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(completed == total ? "— a quiet day, well kept" : "complete")
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
                requestNewHabit(habitCount: 0)
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
        // The paywall promises the Still Moment as a Pro keepsake, so it stays
        // honest: once the grace window closes, the day still completes and
        // the progress bar still fills — the sensory reward simply rests.
        guard store.hasFullAccess else { return }
        CrashDiagnostics.note("still moment")
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

    // MARK: - Purchase celebration

    /// Plays the quiet post-purchase thank-you: a beat of patience while the
    /// paywall cover finishes dismissing, then the sage ripple and drifting
    /// petals bloom over the Today screen for a few seconds and fade out on
    /// their own. Purely additive — nothing is disabled and nothing blocks.
    private func celebratePurchase() {
        CrashDiagnostics.note("pro celebration")
        proCelebrationTask?.cancel()
        proCelebrationTask = Task {
            // The purchase completes while the paywall is still covering the
            // screen; ContentView dismisses it on the same `isPremium` flip.
            // Waiting out that transition means the celebration lands on the
            // Today view itself, not behind a departing cover.
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            playHeartbeatHaptic()
            withAnimation(.easeOut(duration: 0.5)) {
                isProCelebrationActive = true
            }
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                isProCelebrationActive = false
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
                .foregroundStyle(DesignSystem.Colors.softOchre)

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
            present(.resting)
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

// MARK: - Sheet routing

/// Every screen the Today view can present, funnelled through a single
/// `.sheet(item:)` so two presentations can never collide.
enum TodayRoute: Identifiable, Equatable {
    case addHabit
    case resting
    /// The habit detail sheet, identified by habit ID rather than by model —
    /// a deleted SwiftData object read during dismissal aborts the process.
    case detail(UUID)
    case weeklyGraph
    case settings

    var id: String {
        switch self {
        case .addHabit:         return "addHabit"
        case .resting:          return "resting"
        case .detail(let id):   return "detail-\(id.uuidString)"
        case .weeklyGraph:      return "weeklyGraph"
        case .settings:         return "settings"
        }
    }
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
