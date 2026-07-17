//
//  WidgetStore.swift
//  StillhabitWidget
//
//  Opens the same App Group SwiftData store the main app writes to.
//

import Foundation
import SwiftData

enum WidgetStore {
    /// Keep in sync with `SharedStore.appGroupID` in the app target.
    static let appGroupID = "group.app.rork.ruluo6lxh53x1n5ogz4q1"

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(groupContainer: .identifier(appGroupID))
        return try ModelContainer(for: Habit.self, configurations: configuration)
    }

    /// Fetches active (non-archived) habits sorted by creation date.
    static func fetchActiveHabits() -> [Habit] {
        guard let container = try? makeContainer() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
