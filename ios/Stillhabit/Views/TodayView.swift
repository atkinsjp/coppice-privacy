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
    private var habits: [Habit] {
        allHabits.filter { $0.isScheduledForToday }
    }

    @State private var isAddingHabit = false
    @State private var isShowingResting = false
    @State private var isShowingPaywall = false
    @State private var isShowingAmbientSettings = false
    @State private var selectedHabit: Habit?
    @State private var ambientPlayer = AmbientSoundPlayer()

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if habits.isEmpty {
                    emptyState
                } else {
                    progressSection

                    LazyVStack(spacing: DesignSystem.Layout.rowSpacing) {
                        ForEach(habits) { habit in
                            HabitRowView(
                                habit: habit,
                                showsWeeklyProgress: true,
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
            .padding(.top, 12)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateLine)
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(alignment: .center) {
                Text("Today")
                    .font(DesignSystem.Typography.largeHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                ambientButton

                Button {
                    requestNewHabit()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(DesignSystem.Colors.card, in: Circle())
                        .softShadow()
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.sage))
                .accessibilityLabel("New habit")
            }
        }
    }

    // MARK: - Ambient sound

    private var ambientButton: some View {
        Button {
            isShowingAmbientSettings = true
        } label: {
            Image(systemName: ambientPlayer.current.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    ambientPlayer.current == .off
                        ? DesignSystem.Colors.textSecondary
                        : ambientPlayer.current.accent
                )
                .frame(width: 40, height: 40)
                .background(DesignSystem.Colors.card, in: Circle())
                .softShadow()
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.stillTactileWave(accent: ambientPlayer.current.accent))
        .accessibilityLabel(ambientPlayer.current.label)
        .accessibilityHint("Opens ambient sound settings")
        .popover(isPresented: $isShowingAmbientSettings) {
            AmbientSettingsView(player: ambientPlayer)
                .presentationCompactAdaptation(.popover)
        }
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
