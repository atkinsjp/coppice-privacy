//
//  CadencePicker.swift
//  CoppiceHabitsThatRest
//
//  Reusable frequency selector shared by the new-habit sheet and the
//  habit detail editor. Three rounded pills (Every Day / Specific Days /
//  Weekly Goal), a row of seven circular day toggles, and a quiet stepper.
//  Binding-driven so the caller owns the source of truth.
//

import SwiftUI

/// Minimalist cadence selector. Binds to a `HabitCadence` value and an
/// accent color. The caller is responsible for resolving the final cadence
/// (e.g. turning an empty `selectedWeekdays` into `.daily`) on save.
struct CadencePicker: View {
    @Binding var cadence: HabitCadence
    @Binding var selectedWeekdays: Set<Int>
    @Binding var weeklyGoal: Int

    let accent: Color
    var label: String = "Frequency"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label)
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

    // MARK: - Pills

    private func cadencePill(_ option: HabitCadence, label: String) -> some View {
        let isActive = isSameCadenceOption(option)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                switch option {
                case .daily:
                    cadence = .daily
                case .specificDays:
                    cadence = .specificDays(selectedWeekdays.sorted())
                case .weeklyTarget:
                    cadence = .weeklyTarget(weeklyGoal)
                }
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

    /// Compares only the option kind (ignoring payload values) so the pill
    /// highlights correctly regardless of how many days / what target is set.
    private func isSameCadenceOption(_ option: HabitCadence) -> Bool {
        switch (cadence, option) {
        case (.daily, .daily): return true
        case (.specificDays, .specificDays): return true
        case (.weeklyTarget, .weeklyTarget): return true
        default: return false
        }
    }

    // MARK: - Weekday toggles

    /// Row of seven circular S M T W T F S toggles, highlighted in the habit's
    /// accent color when active. `Calendar.current` uses 1...7 Sunday→Saturday.
    private var weekdayToggles: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                let isSelected = selectedWeekdays.contains(day)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isSelected { selectedWeekdays.remove(day) }
                        else { selectedWeekdays.insert(day) }
                    }
                    if case .specificDays = cadence {
                        cadence = .specificDays(selectedWeekdays.sorted())
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
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    weeklyGoal = max(1, weeklyGoal - 1)
                    if case .weeklyTarget = cadence {
                        cadence = .weeklyTarget(weeklyGoal)
                    }
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
                    if case .weeklyTarget = cadence {
                        cadence = .weeklyTarget(weeklyGoal)
                    }
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
