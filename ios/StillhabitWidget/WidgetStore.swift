//
//  WidgetStore.swift
//  StillhabitWidget
//
//  Opens the same App Group SwiftData store the main app writes to.
//

import Foundation
import SwiftData

enum WidgetStore {
    /// Must match both targets' entitlements and `SharedStore.appGroupID` in the app target.
    static let appGroupID = "group.com.atkinsmedia.stillhabit"

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
