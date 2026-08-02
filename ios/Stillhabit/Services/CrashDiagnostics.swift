//
//  CrashDiagnostics.swift
//  Stillhabit
//
//  Four consecutive preview crashes arrived as a bare `signal=6` (SIGABRT)
//  with no symbols and no reason. That happens because the only channels the
//  app was reporting on — `NSLog` and `print` from a release build — are
//  routed to os_log on iOS 26 and never reach the captured runtime stream.
//
//  Everything here now writes to **stderr**, which the preview harness does
//  capture (it is the same stream the `objc[...]` runtime warnings arrive on).
//  Three layers:
//    1. A rolling breadcrumb trail of recent user actions, echoed to stderr as
//       they happen and mirrored to disk so it survives into the next launch.
//    2. An uncaught Objective-C exception handler — the usual source of an
//       abort that no Swift `do/catch` can trap — printing name, reason, and
//       call stack.
//    3. POSIX signal handlers that dump a symbolized backtrace straight to
//       file descriptor 2 before re-raising, so even a pure C/C++ abort deep
//       inside a system framework lands in the crash report with frames.
//
//  Nothing here changes app behavior; it only records.
//

import Foundation
import Darwin

/// Writes one line to stderr. This is the only output channel the preview
/// harness reliably captures, so every diagnostic goes through here.
nonisolated func stillhabitWriteToStandardError(_ text: String) {
    fputs(text.hasSuffix("\n") ? text : text + "\n", stderr)
    fflush(stderr)
}

/// Last-resort crash reporter. Dumps a backtrace to stderr, restores the
/// default disposition, and re-raises so the process still terminates with the
/// original signal (which keeps the harness's own reporting intact).
///
/// Deliberately a free function so it converts to a C function pointer.
nonisolated func stillhabitHandleFatalSignal(_ received: Int32) {
    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 96)
    let frameCount = backtrace(&frames, Int32(frames.count))

    let header = "\n[Stillhabit] FATAL signal \(received) — \(frameCount) frames:\n"
    header.withCString { pointer in
        _ = write(STDERR_FILENO, pointer, strlen(pointer))
    }
    backtrace_symbols_fd(&frames, frameCount, STDERR_FILENO)

    signal(received, SIG_DFL)
    raise(received)
}

/// A short, disk-backed list of recent app events that survives a crash.
nonisolated final class DiagnosticsTrail: @unchecked Sendable {
    private static let maximumEntries = 32

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

    /// Records one event, echoes it to stderr, and flushes the whole trail to
    /// disk immediately so an abort a microsecond later still leaves it readable.
    func append(_ event: String) {
        let stamped = String(format: "%.1fs %@", ProcessInfo.processInfo.systemUptime, event)
        stillhabitWriteToStandardError("[Stillhabit] " + stamped)

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

    /// Signals that mean the process is going down. SIGABRT is the one every
    /// uncaught Objective-C exception funnels through.
    private static let fatalSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGTRAP]

    /// Installs the exception + signal reporters and replays the previous
    /// session's trail. Call once on launch, before any UI is built.
    static func install() {
        stillhabitWriteToStandardError("[Stillhabit] === session start ===")

        if let previous = trail.takePreviousSession() {
            stillhabitWriteToStandardError("[Stillhabit] previous session trail:\n" + previous)
        }

        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(32).joined(separator: "\n")
            let summary = "FATAL uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")"
            stillhabitWriteToStandardError("[Stillhabit] " + summary + "\n" + symbols)
            CrashDiagnostics.trail.append(summary)
        }

        for received in fatalSignals {
            signal(received, stillhabitHandleFatalSignal)
        }

        note("launch")
    }

    /// Records a breadcrumb. Cheap, safe to call from any thread, and never
    /// carries user content — only the name of the action taken.
    static func note(_ event: String) {
        trail.append(event)
    }
}
