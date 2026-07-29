//
//  RestingHabitsView.swift
//  Stillhabit
//
//  Archived habits live here, quietly, until they are welcomed back.
//

import SwiftUI
import SwiftData

struct RestingHabitsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.createdAt)
    private var restingHabits: [Habit]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Resting")
                .font(DesignSystem.Typography.sectionHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.top, 24)

            if restingHabits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text("Nothing is resting right now.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Layout.rowSpacing) {
                        ForEach(restingHabits) { habit in
                            restingRow(habit)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
        .presentationDetents([.medium, .large])
        .presentationBackground(DesignSystem.Colors.background)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func restingRow(_ habit: Habit) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(DesignSystem.habitColor(forHex: habit.colorHex).opacity(0.55))
                .frame(width: 10, height: 10)

            Text(habit.title)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    habit.isArchived = false
                }
                SharedStore.notifyWidgets()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.sage)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Bring back \(habit.title)")

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    modelContext.delete(habit)
                }
                SharedStore.notifyWidgets()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.terracotta)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Delete \(habit.title)")
        }
        .padding(.vertical, 8)
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .background(DesignSystem.Colors.card)
        .clipShape(.rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
        .softShadow()
    }
}

#Preview {
    RestingHabitsView()
        .modelContainer(for: Habit.self, inMemory: true)
}
