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
    private var habits: [Habit]

    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.createdAt)
    private var restingHabits: [Habit]

    @State private var isAddingHabit = false
    @State private var isShowingResting = false
    @State private var isShowingPaywall = false
    @State private var isShowingAmbientSettings = false
    @State private var selectedHabit: Habit?
    @State private var ambientPlayer = AmbientSoundPlayer()

    private var completedCount: Int {
        habits.filter { $0.isCompleted(on: Date()) }.count
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
        .background {
            WavyBackgroundView()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if allComplete {
                peaceMessage
            }
        }
        .animation(.easeInOut(duration: 0.6), value: allComplete)
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

    // MARK: - Peace message

    private var peaceMessage: some View {
        Text("Everything is done for today. Enjoy your peace.")
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
            .padding(.bottom, 20)
            .transition(.opacity)
            .accessibilityAddTraits(.isStaticText)
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
