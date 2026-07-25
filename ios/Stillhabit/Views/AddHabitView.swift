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
    @State private var type: HabitType = .checkIn
    /// Optional intentionality anchor — the user's "why" for this habit.
    @State private var whyString: String = ""
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pro members choose from the full muted palette.
    private var availablePalette: [DesignSystem.HabitColor] {
        store.isPremium ? DesignSystem.palette + DesignSystem.premiumPalette : DesignSystem.palette
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
                    accent: Color(hex: selectedHex)
                )

                HabitTypePicker(
                    type: $type,
                    accent: Color(hex: selectedHex)
                )

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
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.height(store.isPremium ? 760 : 700)])
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
        let habit = Habit(
            title: trimmedTitle,
            colorHex: selectedHex,
            cadence: resolvedCadence,
            type: resolvedType,
            whyString: whyString
        )
        modelContext.insert(habit)
        SharedStore.notifyWidgets()
        dismiss()
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
