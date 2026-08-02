//
//  ContentView.swift
//  Stillhabit
//

import SwiftUI
import SwiftData

/// Root of the app: one focused Today view.
/// No tab bars, no floating buttons — just today.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TodayView()
            .task { await syncReminders() }
    }

    /// Re-registers every stored habit reminder on launch, so the scheduled
    /// notifications always match the saved times even after a device restore,
    /// a timezone change, or the system dropping pending requests.
    private func syncReminders() async {
        ReminderService.shared.prepareSounds()
        let habits = (try? modelContext.fetch(FetchDescriptor<Habit>())) ?? []
        await ReminderService.shared.syncAll(habits)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
}
