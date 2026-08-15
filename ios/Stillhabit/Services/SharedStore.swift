//
//  SharedStore.swift
//  Stillhabit
//
//  SwiftData container living in the shared App Group so the widget
//  extension can read and toggle habits without opening the app.
//  When iCloud is available, the container syncs to CloudKit so habits
//  follow the user across devices automatically.
//

import Foundation
import SwiftData
import WidgetKit

/// The iCloud container identifier used for CloudKit sync.
/// Must match the `com.apple.developer.icloud-container-identifiers`
/// entry in the app's entitlements.
enum CloudKitConfig {
    static let containerIdentifier = "iCloud.com.atkinsmedia.stillhabit"
}

enum SharedStore {
    /// App Group candidates shared between the app and the widget extension, in
    /// preference order. The custom group is used on real devices; the Rork
    /// project group is the one provisioned on the cloud simulator. Must match
    /// both targets' entitlements and `WidgetStore.appGroupIDCandidates`.
    static let appGroupIDCandidates = [
        "group.com.atkinsmedia.stillhabit",
    ]

    /// True when the most recent `makeContainer()` call succeeded with a
    /// CloudKit-enabled configuration. Read by Settings to show sync state.
    private(set) static var isCloudKitEnabled: Bool = false

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

    /// Builds the shared ModelContainer, preferring CloudKit sync when an
    /// iCloud account is available and falling back to a local store if not.
    ///
    /// CloudKit + SwiftData requires every stored attribute to be optional or
    /// have an inline default, and does not support Codable enums with
    /// associated values or arrays of custom Codable structs. The `Habit` model
    /// satisfies these by encoding `cadence`, `type`, and `logs` as `Data?`.
    static func makeContainer() -> ModelContainer {
        if let groupID = resolvedAppGroupID() {
            // Try CloudKit first. This fails silently when there is no iCloud
            // account, the entitlement is missing, or the container is not
            // provisioned (e.g. cloud simulator) -- in those cases we fall
            // back to a plain App Group store so the app still works.
            if let cloudKitContainer = makeCloudKitContainer(groupID: groupID) {
                isCloudKitEnabled = true
                migrateLegacyStoreIfNeeded(into: cloudKitContainer)
                return cloudKitContainer
            }
            isCloudKitEnabled = false

            let groupConfiguration = ModelConfiguration(groupContainer: .identifier(groupID))
            if let container = try? ModelContainer(for: Habit.self, configurations: groupConfiguration) {
                migrateLegacyStoreIfNeeded(into: container)
                return container
            }
        }
        isCloudKitEnabled = false
        do {
            return try ModelContainer(for: Habit.self)
        } catch {
            fatalError("Unable to create any ModelContainer: \(error)")
        }
    }

    /// Attempts to create a CloudKit-synced container in the App Group.
    /// Returns nil if CloudKit is unavailable (no account, missing entitlement,
    /// simulator, or the container can't be opened with the current schema).
    private static func makeCloudKitContainer(groupID: String) -> ModelContainer? {
        let configuration = ModelConfiguration(
            groupContainer: .identifier(groupID),
            cloudKitDatabase: .private(CloudKitConfig.containerIdentifier)
        )
        return try? ModelContainer(for: Habit.self, configurations: configuration)
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
            let copy = Habit(
                title: legacy.title,
                colorHex: legacy.colorHex,
                cadence: legacy.cadence,
                type: legacy.type,
                whyString: legacy.whyString
            )
            copy.id = legacy.id
            copy.createdAt = legacy.createdAt
            copy.completedDates = legacy.completedDates
            copy.isArchived = legacy.isArchived
            copy.logs = legacy.logs
            copy.timerStart = legacy.timerStart
            copy.order = legacy.order
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
    ///
    /// Coalesced and pushed off the main thread on purpose. A reload wakes the
    /// widget extension, which is a **separate process** that opens the very
    /// same App Group SQLite store this app is writing to. Firing it inline
    /// from a button action — several times in a row, as a quick-add or a
    /// reorder does — relaunches that process against a store the app still
    /// holds a write lock on. Batching into one call a beat after the last
    /// change keeps the two processes out of each other's way, and keeps the
    /// WidgetKit XPC round-trip off the main thread entirely.
    static func notifyWidgets() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        reloadWorkItem = work
        reloadQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static let reloadQueue = DispatchQueue(label: "app.stillhabit.widget-reload", qos: .utility)
    nonisolated(unsafe) private static var reloadWorkItem: DispatchWorkItem?
}
