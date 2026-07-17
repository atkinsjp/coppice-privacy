//
//  SharedStore.swift
//  Stillhabit
//
//  SwiftData container living in the shared App Group so the widget
//  extension can read and toggle habits without opening the app.
//

import Foundation
import SwiftData
import WidgetKit

enum SharedStore {
    /// App Group shared between the app and the widget extension.
    /// Keep in sync with `WidgetStore.appGroupID` in the widget target.
    static let appGroupID = "group.app.rork.ruluo6lxh53x1n5ogz4q1"

    /// Builds the shared ModelContainer, falling back to a local store
    /// if the group container is unavailable (e.g. missing entitlement).
    static func makeContainer() -> ModelContainer {
        let groupConfiguration = ModelConfiguration(groupContainer: .identifier(appGroupID))
        if let container = try? ModelContainer(for: Habit.self, configurations: groupConfiguration) {
            return container
        }
        do {
            return try ModelContainer(for: Habit.self)
        } catch {
            fatalError("Unable to create any ModelContainer: \(error)")
        }
    }

    /// Asks WidgetKit to re-render all Stillhabit widgets after data changes.
    static func notifyWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
