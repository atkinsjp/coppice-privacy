//
//  CrashDiagnostics.swift
//  StillHabitCalmHabitTracker
//
//  Records what the app was doing before it died, and makes sure that if it
//  does die, it dies *loudly* rather than silently wedging.
//
//  Three layers:
//    1. A rolling breadcrumb trail of recent user actions, echoed to stderr
//       (the only stream the preview harness captures) and mirrored to disk on
//       a background queue so it survives into the next launch.
//    2. An uncaught Objective-C exception handler — the usual source of an
//       abort that no Swift `do/catch` can trap — printing name, reason, and
//       call stack. This runs in a normal context, so Foundation is fair game.
//    3. A POSIX signal handler that dumps raw return addresses to file
//       descriptor 2 and then re-raises.
//
//  ## Why the signal handler is written the way it is
//
//  The previous version called `backtrace_symbols_fd`, which allocates. A
//  signal handler may only call async-signal-safe functions: `malloc` is not
//  one of them. SIGABRT very often originates *inside* the allocator or with
//  the malloc lock already held (`abort()` from libsystem_malloc, an ObjC
//  exception thrown mid-allocation), and calling back into malloc from the
//  handler then deadlocks. The process stops dead without ever terminating —
//  no crash report is written, and the harness eventually interrupts it and
//  reports "exited after running" with an empty trace. In other words, the
//  reporter was capable of converting a diagnosable crash into an
//  undiagnosable hang.
//
//  Everything below the `install()` boundary is therefore allocation-free:
//  stack-only scratch buffers via `withUnsafeTemporaryAllocation`, raw
//  `write(2)` instead of `fputs`, hand-rolled number formatting, and a
//  re-entrancy guard so a fault inside the handler goes straight to the
//  default disposition instead of recursing.
//
//  Nothing here changes app behavior; it only records.
//

import Foundation
import Darwin

// MARK: - Normal-context output

/// Writes one line to stderr. This is the only output channel the preview
/// harness reliably captures, so every diagnostic goes through here.
///
/// NOT safe from a signal handler — use `stillhabitRawWrite` there.
nonisolated func stillhabitWriteToStandardError(_ text: String) {
    fputs(text.hasSuffix("\n") ? text : text + "\n", stderr)
    fflush(stderr)
}

// MARK: - Async-signal-safe output

/// Raw `write(2)` to stderr, looping over short writes. No buffering, no locks,
/// no allocation — safe to call from a signal handler.
nonisolated private func stillhabitRawWrite(_ bytes: UnsafeRawBufferPointer) {
    guard let base = bytes.baseAddress, bytes.count > 0 else { return }
    var offset = 0
    while offset < bytes.count {
        let written = write(STDERR_FILENO, base + offset, bytes.count - offset)
        guard written > 0 else { return }
        offset += written
    }
}

/// Writes a compile-time constant string. `StaticString` carries its own UTF-8
/// buffer, so nothing is allocated at call time.
nonisolated private func stillhabitRawWrite(_ text: StaticString) {
    text.withUTF8Buffer { buffer in
        stillhabitRawWrite(UnsafeRawBufferPointer(buffer))
    }
}

/// Writes a small non-negative integer in decimal, digits built on the stack.
nonisolated private func stillhabitRawWriteDecimal(_ value: Int32) {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 12) { scratch in
        scratch.initialize(repeating: 0)
        var remaining = value < 0 ? 0 : value
        var index = scratch.count
        repeat {
            index -= 1
            scratch[index] = UInt8(ascii: "0") + UInt8(remaining % 10)
            remaining /= 10
        } while remaining > 0 && index > 0
        guard let base = scratch.baseAddress else { return }
        stillhabitRawWrite(UnsafeRawBufferPointer(start: base + index, count: scratch.count - index))
    }
}

/// Writes a pointer-sized value as `0x…` hex, digits built on the stack.
nonisolated private func stillhabitRawWriteHex(_ value: UInt) {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 18) { scratch in
        scratch.initialize(repeating: 0)
        scratch[0] = UInt8(ascii: "0")
        scratch[1] = UInt8(ascii: "x")
        var index = 2
        var hasLeadingDigit = false
        var shift = 60
        while shift >= 0 {
            let nibble = UInt8((value >> UInt(shift)) & 0xF)
            if nibble != 0 || hasLeadingDigit || shift == 0 {
                hasLeadingDigit = true
                scratch[index] = nibble < 10
                    ? UInt8(ascii: "0") + nibble
                    : UInt8(ascii: "a") + (nibble - 10)
                index += 1
            }
            shift -= 4
        }
        guard let base = scratch.baseAddress else { return }
        stillhabitRawWrite(UnsafeRawBufferPointer(start: base, count: index))
    }
}

/// Set once the handler is running so a fault raised *inside* it can't recurse.
nonisolated(unsafe) private var stillhabitIsHandlingFatalSignal = false

/// Last-resort crash reporter.
///
/// Dumps the raw return addresses of the crashing thread to stderr, restores
/// the default disposition, and re-raises so the process still terminates with
/// the original signal (which keeps the harness's own reporting intact).
/// Addresses are unsymbolicated on purpose: symbolication allocates, and an
/// allocation here can deadlock the whole process (see the file comment).
///
/// Deliberately a free function so it converts to a C function pointer.
nonisolated func stillhabitHandleFatalSignal(_ received: Int32) {
    if stillhabitIsHandlingFatalSignal {
        signal(received, SIG_DFL)
        raise(received)
        return
    }
    stillhabitIsHandlingFatalSignal = true

    stillhabitRawWrite("\n[StillHabitCalmHabitTracker] FATAL signal ")
    stillhabitRawWriteDecimal(received)
    stillhabitRawWrite(" — return addresses:\n")

    withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer?.self, capacity: 64) { frames in
        frames.initialize(repeating: nil)
        guard let base = frames.baseAddress else { return }
        let frameCount = Int(backtrace(base, Int32(frames.count)))
        for index in 0..<max(0, min(frameCount, frames.count)) {
            stillhabitRawWriteHex(UInt(bitPattern: frames[index]))
            stillhabitRawWrite("\n")
        }
    }

    signal(received, SIG_DFL)
    raise(received)
}

// MARK: - Breadcrumbs

/// A short, disk-backed list of recent app events that survives a crash.
nonisolated final class DiagnosticsTrail: @unchecked Sendable {
    private static let maximumEntries = 32

    private let lock = NSLock()
    private var entries: [String] = []
    private let fileURL: URL?
    /// Breadcrumbs are recorded from the main thread during user interaction,
    /// so the file write is pushed off it — a synchronous atomic write per tap
    /// is main-thread disk I/O the UI does not need to wait on.
    private let writeQueue = DispatchQueue(label: "app.stillhabit.diagnostics", qos: .utility)

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

    /// Records one event and echoes it to stderr. The trail is flushed to disk
    /// asynchronously so a crash a moment later still leaves it readable
    /// without the UI paying for the write.
    func append(_ event: String) {
        let stamped = String(format: "%.1fs %@", ProcessInfo.processInfo.systemUptime, event)
        stillhabitWriteToStandardError("[StillHabitCalmHabitTracker] " + stamped)

        lock.lock()
        entries.append(stamped)
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        let snapshot = entries.joined(separator: "\n")
        lock.unlock()

        guard let fileURL else { return }
        writeQueue.async {
            try? Data(snapshot.utf8).write(to: fileURL, options: .atomic)
        }
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
        stillhabitWriteToStandardError("[StillHabitCalmHabitTracker] === session start ===")

        if let previous = trail.takePreviousSession() {
            stillhabitWriteToStandardError("[StillHabitCalmHabitTracker] previous session trail:\n" + previous)
        }

        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(32).joined(separator: "\n")
            let summary = "FATAL uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")"
            stillhabitWriteToStandardError("[StillHabitCalmHabitTracker] " + summary + "\n" + symbols)
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
