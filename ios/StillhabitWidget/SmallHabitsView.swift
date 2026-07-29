//
//  SmallHabitsView.swift
//  StillhabitWidget
//
//  A quiet completion ring ("2 of 3") with a single pill button
//  that logs the top uncompleted habit. Fixed frames — no layout shift.
//

import SwiftUI
import WidgetKit

struct SmallHabitsView: View {
    let entry: HabitEntry

    private var fraction: Double {
        entry.totalCount == 0 ? 0 : Double(entry.completedCount) / Double(entry.totalCount)
    }

    private var ringAccent: Color {
        if let top = entry.topUncompleted {
            return WidgetDesign.habitColor(forHex: top.colorHex)
        }
        return WidgetDesign.sage
    }

    var body: some View {
        VStack(spacing: 10) {
            ring
            actionSlot
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(WidgetDesign.textSecondary.opacity(0.15), lineWidth: 6)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text("\(entry.completedCount)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetDesign.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(entry.totalCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetDesign.textSecondary)
            }
        }
        .frame(width: 68, height: 68)
        .invalidatableContent()
        .accessibilityLabel("\(entry.completedCount) of \(entry.totalCount) habits complete")
    }

    // MARK: - Action slot (fixed 28pt tall in every state)

    @ViewBuilder
    private var actionSlot: some View {
        if entry.totalCount == 0 {
            Text("Begin in the app")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(WidgetDesign.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        } else if let top = entry.topUncompleted {
            Button(intent: ToggleHabitIntent(habitID: top.id)) {
                Text(top.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetDesign.onAccent)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(WidgetDesign.habitColor(forHex: top.colorHex), in: Capsule())
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            .accessibilityLabel("Log \(top.title)")
        } else {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("All done")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(WidgetDesign.sage)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
    }
}
