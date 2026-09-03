//
//  AddHabitView.swift
//  CoppiceHabitsThatRest
//

import SwiftUI
import SwiftData

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreViewModel.self) private var store

    @State private var title = ""
    @State private var selectedHex: String = DesignSystem.palette[0].hex
    @State private var cadence: HabitCadence = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var weeklyGoal: Int = 3
    @State private var type: HabitType = .checkIn
    /// Optional intentionality anchor — the user's "why" for this habit.
    @State private var whyString: String = ""
    /// Optional time-of-day reminder for this habit.
    @State private var isReminderEnabled: Bool = false
    @State private var reminderTime: Date = Habit.date(fromMinuteOfDay: 8 * 60)
    /// The tone this habit's reminder will play.
    @State private var reminderSound: ReminderSound = .chime
    /// The vibration signature this habit's reminder will play.
    @State private var reminderHaptic: ReminderHaptic = .breath
    /// Latched the instant a save begins. A second tap on "Begin" (or Return on
    /// the keyboard while the first save is already under way) would otherwise
    /// insert the habit twice **and** call `dismiss()` on a sheet that is
    /// already mid-dismissal — UIKit answers a redundant dismissal with an
    /// Objective-C exception that no Swift `do/catch` can trap, which aborts
    /// the process. Nothing about the first tap is visible instantly, so a
    /// second tap is the most natural thing in the world here.
    @State private var isSaving = false
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pro members — and anyone still inside the 72-hour local grace window —
    /// choose from the full muted palette.
    private var availablePalette: [DesignSystem.HabitColor] {
        store.hasFullAccess ? DesignSystem.palette + DesignSystem.premiumPalette : DesignSystem.palette
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("New habit")
                    .font(DesignSystem.Typography.sectionHeader)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(.top, 8)

                TextField("What would you like to nurture?", text: $title)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(16)
                    .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        if !trimmedTitle.isEmpty { save() }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("The Why (Optional)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.leading, 4)

                    TextField("e.g., To wake up clear and rested for my family.", text: $whyString, axis: .vertical)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DesignSystem.Colors.textPrimary.opacity(0.85))
                        .lineLimit(1...3)
                        .padding(16)
                        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.Layout.fieldCornerRadius)
                                .strokeBorder(DesignSystem.Colors.textSecondary.opacity(0.18), lineWidth: 0.5)
                        }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(availablePalette) { habitColor in
                        colorSwatch(habitColor)
                    }
                }

                CadencePicker(
                    cadence: $cadence,
                    selectedWeekdays: $selectedWeekdays,
                    weeklyGoal: $weeklyGoal,
                    accent: DesignSystem.habitColor(forHex: selectedHex)
                )

                HabitTypePicker(
                    type: $type,
                    accent: DesignSystem.habitColor(forHex: selectedHex)
                )

                ReminderPicker(
                    isEnabled: $isReminderEnabled,
                    time: $reminderTime,
                    sound: $reminderSound,
                    haptic: $reminderHaptic,
                    accent: DesignSystem.habitColor(forHex: selectedHex),
                    cadence: cadence
                )
                .onChange(of: isReminderEnabled) { _, newValue in
                    guard newValue else { return }
                    Task {
                        let granted = await ReminderService.shared.requestAuthorization()
                        if !granted, ReminderService.shared.authorizationStatus != .denied {
                            withAnimation(.easeOut(duration: 0.2)) { isReminderEnabled = false }
                        }
                    }
                }

                Button(action: save) {
                    Text("Begin")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DesignSystem.habitColor(forHex: selectedHex), in: Capsule())
                }
                .buttonStyle(.stillTactileWave(accent: DesignSystem.habitColor(forHex: selectedHex)))
                .disabled(trimmedTitle.isEmpty || isSaving)
                .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
                .animation(.easeOut(duration: 0.2), value: trimmedTitle.isEmpty)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .presentationBackground(DesignSystem.Colors.background)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .task {
            // Installing a first responder while the sheet is still animating
            // in makes UIKit attach the keyboard to a view controller that is
            // mid-presentation. A beat later the transition has settled.
            try? await Task.sleep(for: .milliseconds(350))
            // If the sheet was dismissed inside that window the task is
            // cancelled — but `try?` swallows the cancellation, so without this
            // check we would install a first responder on a view controller
            // that is being torn down.
            guard !Task.isCancelled, !isSaving else { return }
            isTitleFocused = true
        }
    }

    private func colorSwatch(_ habitColor: DesignSystem.HabitColor) -> some View {
        let isSelected = habitColor.hex == selectedHex
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedHex = habitColor.hex
            }
        } label: {
            Circle()
                .fill(habitColor.color)
                .frame(width: 34, height: 34)
                .overlay {
                    Circle()
                        .stroke(DesignSystem.Colors.textPrimary.opacity(isSelected ? 0.35 : 0), lineWidth: 2)
                        .padding(-5)
                }
                .scaleEffect(isSelected ? 1.08 : 1)
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.stillTactileWave(accent: habitColor.color))
        .accessibilityLabel(habitColor.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        guard !trimmedTitle.isEmpty, !isSaving else { return }
        isSaving = true
        CrashDiagnostics.note("save new habit")

        // Give up the keyboard first. Tearing a first responder down inside
        // the same transaction that dismisses the sheet is a UIKit hazard, and
        // the field is about to disappear regardless.
        isTitleFocused = false

        let resolvedCadence: HabitCadence
        switch cadence {
        case .daily:
            resolvedCadence = .daily
        case .specificDays:
            let sorted = selectedWeekdays.sorted()
            resolvedCadence = sorted.isEmpty ? .daily : .specificDays(sorted)
        case .weeklyTarget:
            resolvedCadence = .weeklyTarget(max(1, min(weeklyGoal, 6)))
        }
        let nextOrder = nextHabitOrder()
        let habit = Habit(
            title: trimmedTitle,
            colorHex: selectedHex,
            cadence: resolvedCadence,
            type: resolvedType,
            whyString: whyString,
            order: nextOrder
        )
        if isReminderEnabled {
            habit.reminderMinuteOfDay = Habit.minuteOfDay(from: reminderTime)
            habit.reminderSound = reminderSound
            habit.reminderHaptic = reminderHaptic
        }
        modelContext.insert(habit)

        // Persist immediately instead of waiting for autosave. A habit the
        // user just created has to survive whatever happens next — an autosave
        // that never runs means the habit is silently gone on relaunch.
        do {
            try modelContext.save()
        } catch {
            print("AddHabitView: could not persist new habit — \(error.localizedDescription)")
        }

        // Snapshot the reminder now, while the model is guaranteed alive.
        // `ReminderPlan` is an inert Sendable value, so the scheduling work can
        // outlive this sheet without ever reading the SwiftData object again.
        let plan = isReminderEnabled ? ReminderPlan(habit: habit) : nil
        let habitID = habit.id

        // Hand the dismissal to the next main-actor turn.
        //
        // This method runs inside a SwiftUI button action, which UIKit invokes
        // from the middle of touch delivery — and the keyboard is almost always
        // up, because the title field auto-focuses. Resigning a first responder
        // and starting a sheet dismissal inside that same transaction makes
        // UIKit tear the keyboard's remote view down while the sheet's own
        // transition is being installed. One turn later both the touch and the
        // keyboard resignation have finished, and the dismissal is the only
        // thing happening.
        Task { @MainActor in
            dismiss()

            // Side effects run after the dismissal is under way, so neither the
            // widget reload nor the notification centre round-trip lands in the
            // middle of the presentation transaction.
            SharedStore.notifyWidgets()
            if plan != nil {
                await ReminderService.shared.apply(plan, for: habitID)
            }
        }
    }

    /// Computes the next manual order value so a newly created habit is
    /// appended after all existing non-archived habits in the Today list.
    private func nextHabitOrder() -> Int {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count
    }

    /// Normalizes the chosen type so a numeric habit always has a positive
    /// target and a non-empty unit, and a duration habit always has a sane
    /// minute target. `.checkIn` passes through untouched.
    private var resolvedType: HabitType {
        switch type {
        case .checkIn:
            return .checkIn
        case .numeric(let target, let unit):
            let cleanedUnit = unit.trimmingCharacters(in: .whitespaces)
            return .numeric(target: max(1, target), unit: cleanedUnit.isEmpty ? "units" : cleanedUnit)
        case .duration(let minutes):
            return .duration(targetMinutes: max(1, min(120, minutes)))
        }
    }

}

#Preview {
    AddHabitView()
        .modelContainer(for: Habit.self, inMemory: true)
        .environment(StoreViewModel())
}
