//
//  ReminderPicker.swift
//  Stillhabit
//
//  Reusable time-of-day reminder selector shared by the new-habit sheet and
//  the habit detail editor. A quiet toggle reveals a compact time field and
//  three gentle presets. Binding-driven so the caller owns the source of truth
//  and decides when to persist + reschedule.
//

import SwiftUI
import UIKit

struct ReminderPicker: View {
    /// Whether a reminder should exist at all.
    @Binding var isEnabled: Bool
    /// The reminder time. Only the hour and minute are meaningful.
    @Binding var time: Date

    let accent: Color
    var label: String = "Reminder"
    /// Cadence context, used only for the human-readable summary line.
    var cadence: HabitCadence = .daily

    @State private var reminders = ReminderService.shared

    /// Gentle time presets — morning light, midday pause, evening wind-down.
    private static let presets: [(name: String, symbol: String, minute: Int)] = [
        ("Morning", "sun.horizon", 7 * 60),
        ("Midday", "sun.max", 13 * 60),
        ("Evening", "moon", 20 * 60),
    ]

    private var summaryLine: String {
        guard isEnabled else { return "Off" }
        let timeText = time.formatted(date: .omitted, time: .shortened)
        switch cadence {
        case .daily, .weeklyTarget:
            return "Every day at \(timeText)"
        case .specificDays(let days):
            guard !days.isEmpty else { return "Every day at \(timeText)" }
            return "\(Habit.weekdaySummary(days)) at \(timeText)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Text(summaryLine)
                    .font(DesignSystem.Typography.smallNumber)
                    .foregroundStyle(isEnabled ? accent : DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.opacity)
            }

            toggleRow

            if isEnabled {
                timeRow
                presetRow

                if reminders.isDenied {
                    deniedNotice
                }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isEnabled)
        .animation(.easeOut(duration: 0.25), value: reminders.isDenied)
        .task { await reminders.refreshAuthorizationStatus() }
    }

    // MARK: - Toggle

    private var toggleRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isEnabled ? accent.opacity(0.16) : DesignSystem.Colors.textSecondary.opacity(0.12))
                    .frame(width: 34, height: 34)

                Image(systemName: isEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isEnabled ? accent : DesignSystem.Colors.textSecondary)
                    .symbolEffect(.bounce, value: isEnabled)
            }

            Text("Nudge me at a set time")
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(accent)
                .accessibilityLabel("Reminder")
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Layout.fieldCornerRadius)
                .strokeBorder(accent.opacity(isEnabled ? 0.28 : 0.10), lineWidth: 0.75)
        }
    }

    // MARK: - Time

    private var timeRow: some View {
        HStack(spacing: 12) {
            Text("Time")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(accent)
                .accessibilityLabel("Reminder time")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(Self.presets, id: \.name) { preset in
                presetPill(preset)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func presetPill(_ preset: (name: String, symbol: String, minute: Int)) -> some View {
        let isActive = Habit.minuteOfDay(from: time) == preset.minute
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                time = Habit.date(fromMinuteOfDay: preset.minute)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 12)
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
        .accessibilityLabel("\(preset.name) reminder")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Denied

    /// Shown only when the system has notifications turned off for Stillhabit.
    private var deniedNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.terracotta)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are off for Stillhabit, so this reminder won't arrive.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignSystem.Colors.terracotta)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.terracotta.opacity(0.08), in: .rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
