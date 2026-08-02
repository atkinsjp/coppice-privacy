//
//  CrashDiagnostics.swift
//  Stillhabit
//
//  A SIGABRT from an uncaught Objective-C exception (Core Data faults,
//  UIKit presentation errors, audio-session aborts) leaves nothing behind in
//  the preview crash report except a signal number — no symbols, no reason.
//
//  Two things fix that:
//    1. An uncaught-exception handler that writes the exception name, reason,
//       and call stack out before the process dies.
//    2. A rolling breadcrumb trail of the last few meaningful actions, written
//       to disk as they happen and echoed to the device log. Whatever the app
//       was doing in the instants before an abort survives the crash and is
//       reported on the next launch.
//
//  Nothing here changes app behavior; it only records.
//

import Foundation

/// A short, disk-backed list of recent app events that survives a crash.
nonisolated final class DiagnosticsTrail: @unchecked Sendable {
    private static let maximumEntries = 24

    private let lock = NSLock()
    private var entries: [String] = []
    private let fileURL: URL?

    init() {
        fileURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("stillhabit-session-trail.log")
    }

    /// Reads whatever the previous run left behind and clears it.
    func takePreviousSession() -> String? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return text
    }

    /// Records one event and flushes the whole trail to disk immediately, so
    /// an abort a microsecond later still leaves it readable.
    func append(_ event: String) {
        let stamped = String(format: "%.1fs %@", ProcessInfo.processInfo.systemUptime, event)
        lock.lock()
        entries.append(stamped)
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        let snapshot = entries.joined(separator: "\n")
        lock.unlock()

        guard let fileURL else { return }
        try? Data(snapshot.utf8).write(to: fileURL, options: .atomic)
    }
}

nonisolated enum CrashDiagnostics {
    static let trail = DiagnosticsTrail()

    /// Installs the uncaught Objective-C exception handler and reports the
    /// previous session's trail. Call once on launch, before any UI is built.
    static func install() {
        if let previous = trail.takePreviousSession() {
            NSLog("[Stillhabit] previous session trail:\n%@", previous)
        }

        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(24).joined(separator: "\n")
            let summary = "FATAL uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")"
            CrashDiagnostics.trail.append(summary + "\n" + symbols)
            NSLog("[Stillhabit] %@\n%@", summary, symbols)
        }

        note("launch")
    }

    /// Records a breadcrumb. Cheap, safe to call from any thread, and never
    /// carries user content — only the name of the action taken.
    static func note(_ event: String) {
        trail.append(event)
        #if DEBUG
        NSLog("[Stillhabit] %@", event)
        #endif
    }
}
