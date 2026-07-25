//
//  AddHabitView.swift
//  Stillhabit
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
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pro members choose from the full muted palette.
    private var availablePalette: [DesignSystem.HabitColor] {
        store.isPremium ? DesignSystem.palette + DesignSystem.premiumPalette : DesignSystem.palette
    }

    var body: some View {
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(availablePalette) { habitColor in
                    colorSwatch(habitColor)
                }
            }

            cadenceSection

            Button(action: save) {
                Text("Begin")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: selectedHex), in: Capsule())
            }
            .buttonStyle(.stillTactileWave(accent: Color(hex: selectedHex)))
            .disabled(trimmedTitle.isEmpty)
            .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
            .animation(.easeOut(duration: 0.2), value: trimmedTitle.isEmpty)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
        .padding(.top, 16)
        .presentationDetents([.height(store.isPremium ? 568 : 508)])
        .presentationBackground(DesignSystem.Colors.background)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .onAppear { isTitleFocused = true }
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
        guard !trimmedTitle.isEmpty else { return }
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
        let habit = Habit(title: trimmedTitle, colorHex: selectedHex, cadence: resolvedCadence)
        modelContext.insert(habit)
        SharedStore.notifyWidgets()
        dismiss()
    }

    // MARK: - Cadence picker

    /// Minimalist frequency selector: three rounded pills (Every Day /
    /// Specific Days / Weekly Goal). The active pill fills with the habit's
    /// chosen accent color. Selecting "Specific Days" reveals a row of seven
    /// circular day-of-week toggles; "Weekly Goal" reveals a quiet stepper.
    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Frequency")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(spacing: 8) {
                cadencePill(.daily, label: "Every Day")
                cadencePill(.specificDays([]), label: "Specific Days")
                cadencePill(.weeklyTarget(3), label: "Weekly Goal")
            }

            if case .specificDays = cadence {
                weekdayToggles
            } else if case .weeklyTarget = cadence {
                weeklyGoalStepper
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: cadence)
    }

    private func cadencePill(_ option: HabitCadence, label: String) -> some View {
        let isActive = isSameCadenceOption(option)
        let accent = Color(hex: selectedHex)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                cadence = option
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if isActive {
                            Capsule().fill(accent)
                        } else {
                            Capsule().fill(DesignSystem.Colors.card)
                        }
                    }
                )
        }
        .buttonStyle(.stillTactileWave(accent: accent))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Compares only the *option kind* (ignoring payload values) so the pill
    /// highlights correctly regardless of how many days / what target is set.
    private func isSameCadenceOption(_ option: HabitCadence) -> Bool {
        switch (cadence, option) {
        case (.daily, .daily): return true
        case (.specificDays, .specificDays): return true
        case (.weeklyTarget, .weeklyTarget): return true
        default: return false
        }
    }

    /// Row of seven circular S M T W T F S toggles, highlighted in the habit's
    /// accent color when active. `Calendar.current` uses 1...7 Sunday→Saturday.
    private var weekdayToggles: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        let accent = Color(hex: selectedHex)
        return HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selectedWeekdays.contains(day)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isSelected { selectedWeekdays.remove(day) }
                        else { selectedWeekdays.insert(day) }
                    }
                } label: {
                    Text(labels[day - 1])
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(
                            Group {
                                if isSelected {
                                    Circle().fill(accent)
                                } else {
                                    Circle().fill(DesignSystem.Colors.card)
                                }
                            }
                        )
                }
                .buttonStyle(.stillTactileWave(accent: accent))
                .accessibilityLabel(weekdayName(for: day))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var weeklyGoalStepper: some View {
        let accent = Color(hex: selectedHex)
        return HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    weeklyGoal = max(1, weeklyGoal - 1)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.Colors.card, in: Circle())
            }
            .buttonStyle(.stillTactileWave(accent: accent))
            .disabled(weeklyGoal <= 1)
            .accessibilityLabel("Decrease weekly goal")

            Text("\(weeklyGoal)\u{2009}times a week")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    weeklyGoal = min(6, weeklyGoal + 1)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.Colors.card, in: Circle())
            }
            .buttonStyle(.stillTactileWave(accent: accent))
            .disabled(weeklyGoal >= 6)
            .accessibilityLabel("Increase weekly goal")
        }
    }

    private func weekdayName(for index: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard index >= 1, index <= symbols.count else { return "Day" }
        return symbols[index - 1]
    }
}

#Preview {
    AddHabitView()
        .modelContainer(for: Habit.self, inMemory: true)
        .environment(StoreViewModel())
}
