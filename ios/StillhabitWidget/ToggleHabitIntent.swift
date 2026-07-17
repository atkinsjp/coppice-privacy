//
//  ToggleHabitIntent.swift
//  StillhabitWidget
//
//  Interactive widget intent: toggles a habit's completion for today
//  directly in the shared SwiftData store, without opening the app.
//

import AppIntents
import SwiftData
import WidgetKit

struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Habit"
    static let description = IntentDescription("Marks a habit complete or incomplete for today.")

    @Parameter(title: "Habit ID")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: habitID) else { return .result() }

        let container = try WidgetStore.makeContainer()
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == uuid })

        if let habit = try context.fetch(descriptor).first {
            habit.toggleCompletion(on: Date())
            try context.save()
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
