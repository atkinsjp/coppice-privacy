//
//  WidgetStore.swift
//  StillhabitWidget
//
//  Opens the same App Group SwiftData store the main app writes to.
//  The widget intentionally does NOT use CloudKit — extensions have
//  limited execution time and can't maintain a sync session. The widget
//  reads and writes locally; the main app's CloudKit sync picks up any
//  widget-side changes on its next run.
//

import Foundation
import SwiftData

enum WidgetStore {
    /// Must match both targets' entitlements and `SharedStore.appGroupIDCandidates`
    /// in the app target — same candidates, same order, same writability probe,
    /// so both processes always resolve the same container.
    static let appGroupIDCandidates = [
        "group.com.atkinsmedia.stillhabit",
    ]

    /// First app group whose container is actually writable in this environment.
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

    /// Opens the shared App Group store WITHOUT CloudKit. The main app adds
    /// CloudKit sync on top of the same SQLite file; the widget just reads
    /// and writes locally, and those changes are synced up by the main app.
    static func makeContainer() throws -> ModelContainer {
        guard let groupID = resolvedAppGroupID() else {
            return try ModelContainer(for: Habit.self)
        }
        let configuration = ModelConfiguration(groupContainer: .identifier(groupID))
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
