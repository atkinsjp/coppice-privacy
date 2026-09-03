//
//  HabitTypePicker.swift
//  CoppiceHabitsThatRest
//
//  Reusable measurement selector shared by the new-habit sheet and the
//  habit detail editor. Three rounded pills (Yes / No · Count · Timer),
//  plus quiet inputs for the numeric target+unit and the duration target.
//  Binding-driven so the caller owns the source of truth.
//

import SwiftUI

/// Minimalist habit-type selector. Binds to a `HabitType` value and an
/// accent color. The caller is responsible for clamping/finalizing the
/// value (e.g. a positive numeric target) on save.
struct HabitTypePicker: View {
    @Binding var type: HabitType

    /// Scratch state for the numeric target/unit. Kept here so the picker
    /// owns the editing UX while the caller still controls when the value
    /// is promoted into the bound `type`.
    @State private var numericTarget: Double = 8
    @State private var numericUnit: String = "glasses"
    @State private var durationMinutes: Int = 20

    let accent: Color
    var label: String = "Track as"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(spacing: 8) {
                typePill(.checkIn, label: "Yes / No", icon: "checkmark.circle")
                typePill(.numeric(target: numericTarget, unit: numericUnit), label: "Count", icon: "number")
                typePill(.duration(targetMinutes: durationMinutes), label: "Timer", icon: "timer")
            }

            switch type {
            case .checkIn:
                EmptyView()
            case .numeric:
                numericInputs
            case .duration:
                durationStepper
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: type)
        .onAppear { seedScratch() }
        .onChange(of: type) { _, _ in seedScratch() }
    }

    // MARK: - Pills

    private func typePill(_ option: HabitType, label: String, icon: String) -> some View {
        let isActive = isSameTypeOption(option)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                promoteScratch(into: option)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isActive ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary)
            .frame(height: 48)
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
    /// highlights correctly regardless of the current target value.
    private func isSameTypeOption(_ option: HabitType) -> Bool {
        switch (type, option) {
        case (.checkIn, .checkIn): return true
        case (.numeric, .numeric): return true
        case (.duration, .duration): return true
        default: return false
        }
    }

    // MARK: - Numeric inputs

    private var numericInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Target")
                        .font(DesignSystem.Typography.overline)
                        .tracking(1.2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    TextField("8", text: targetText)
                        .keyboardType(.decimalPad)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(12)
                        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit")
                        .font(DesignSystem.Typography.overline)
                        .tracking(1.2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    TextField("glasses, oz, pages…", text: $numericUnit)
                        .font(DesignSystem.Typography.label)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(12)
                        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
                        .onChange(of: numericUnit) { _, _ in
                            promoteScratch(into: .numeric(target: numericTarget, unit: numericUnit))
                        }
                }
            }

            Text("Quick-add pills on the card will be sized to this target.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.85))
        }
    }

    /// A lightweight target field that parses a decimal and promotes it into
    /// the bound type. Kept as a computed binding so the live value always
    /// reflects the scratch state.
    private var targetText: Binding<String> {
        Binding(
            get: { ValueFormatter.wholeOrDecimal(numericTarget) },
            set: { newValue in
                let parsed = Double(newValue.replacingOccurrences(of: ",", with: "."))
                if let parsed, parsed > 0 {
                    numericTarget = parsed
                    promoteScratch(into: .numeric(target: parsed, unit: numericUnit))
                }
            }
        )
    }

    // MARK: - Duration stepper

    private var durationStepper: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    durationMinutes = max(1, durationMinutes - 5)
                    promoteScratch(into: .duration(targetMinutes: durationMinutes))
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.Colors.card, in: Circle())
            }
            .buttonStyle(.stillTactileWave(accent: accent))
            .disabled(durationMinutes <= 5)
            .accessibilityLabel("Decrease focus length")

            Text("\(durationMinutes)\u{2009}minutes")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    durationMinutes = min(120, durationMinutes + 5)
                    promoteScratch(into: .duration(targetMinutes: durationMinutes))
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(DesignSystem.Colors.card, in: Circle())
            }
            .buttonStyle(.stillTactileWave(accent: accent))
            .disabled(durationMinutes >= 120)
            .accessibilityLabel("Increase focus length")
        }
    }

    // MARK: - Scratch sync

    /// Seeds the local editing fields from the bound type so the picker
    /// shows the current values before the user touches anything.
    private func seedScratch() {
        switch type {
        case .checkIn:
            break
        case .numeric(let target, let unit):
            numericTarget = max(1, target)
            if !unit.isEmpty { numericUnit = unit }
        case .duration(let minutes):
            durationMinutes = max(1, minutes)
        }
    }

    /// Writes the current scratch values into the bound `type` for the
    /// given option kind. This is what the pills and steppers call so the
    /// caller's binding always carries the latest payload.
    private func promoteScratch(into option: HabitType) {
        switch option {
        case .checkIn:
            type = .checkIn
        case .numeric:
            let clamped = max(1, numericTarget)
            type = .numeric(target: clamped, unit: numericUnit.trimmingCharacters(in: .whitespaces))
        case .duration:
            let clamped = max(1, min(120, durationMinutes))
            type = .duration(targetMinutes: clamped)
        }
    }
}
