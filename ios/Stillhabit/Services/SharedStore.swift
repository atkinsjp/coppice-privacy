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
    /// App Group candidates shared between the app and the widget extension, in
    /// preference order. The custom group is used on real devices; the Rork
    /// project group is the one provisioned on the cloud simulator. Must match
    /// both targets' entitlements and `WidgetStore.appGroupIDCandidates`.
    static let appGroupIDCandidates = [
        "group.com.atkinsmedia.stillhabit",
        "group.app.rork.ruluo6lxh53x1n5ogz4q1",
    ]

    /// First app group whose container is actually writable in this environment.
    /// The cloud simulator sandbox denies writes inside non-provisioned group
    /// containers, so each candidate is probed before being trusted.
    static func resolvedAppGroupID() -> String? {
        let fileManager = FileManager.default
        for groupID in appGroupIDCandidates {
            guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { continue }
            let supportURL = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            do {
                try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
            } catch {
                continue
            }
            let probeURL = supportURL.appendingPathComponent(".stillhabit-write-probe")
            if fileManager.createFile(atPath: probeURL.path, contents: Data()) {
                try? fileManager.removeItem(at: probeURL)
                return groupID
            }
        }
        return nil
    }

    /// Builds the shared ModelContainer, falling back to a local store
    /// if no group container is writable (e.g. missing entitlement).
    static func makeContainer() -> ModelContainer {
        if let groupID = resolvedAppGroupID() {
            let groupConfiguration = ModelConfiguration(groupContainer: .identifier(groupID))
            if let container = try? ModelContainer(for: Habit.self, configurations: groupConfiguration) {
                migrateLegacyStoreIfNeeded(into: container)
                return container
            }
        }
        do {
            return try ModelContainer(for: Habit.self)
        } catch {
            fatalError("Unable to create any ModelContainer: \(error)")
        }
    }

    /// One-time migration: earlier builds fell back to the app-private default
    /// store, so habits created there are invisible to the widget. If the shared
    /// group store is empty but the legacy local store has habits, copy them over.
    private static func migrateLegacyStoreIfNeeded(into container: ModelContainer) {
        let context = ModelContext(container)
        let existingCount = (try? context.fetchCount(FetchDescriptor<Habit>())) ?? 0
        guard existingCount == 0 else { return }

        guard let legacyContainer = try? ModelContainer(for: Habit.self) else { return }
        let legacyContext = ModelContext(legacyContainer)
        guard let legacyHabits = try? legacyContext.fetch(FetchDescriptor<Habit>()),
              !legacyHabits.isEmpty else { return }

        for legacy in legacyHabits {
            let copy = Habit(title: legacy.title, colorHex: legacy.colorHex)
            copy.id = legacy.id
            copy.createdAt = legacy.createdAt
            copy.completedDates = legacy.completedDates
            copy.isArchived = legacy.isArchived
            context.insert(copy)
        }

        do {
            try context.save()
            try? legacyContext.delete(model: Habit.self)
            try? legacyContext.save()
        } catch {
            print("SharedStore: legacy migration failed — \(error.localizedDescription)")
        }
    }

    /// Asks WidgetKit to re-render all Stillhabit widgets after data changes.
    static func notifyWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
