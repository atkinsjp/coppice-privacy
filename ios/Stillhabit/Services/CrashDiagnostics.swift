//
//  CrashDiagnostics.swift
//  Stillhabit
//
//  A SIGABRT from an uncaught Objective-C exception (Core Data faults,
//  UIKit presentation errors, audio-session aborts) leaves nothing behind in
//  the preview crash report except a signal number. Installing an uncaught
//  exception handler writes the name, reason, and call stack to the device
//  log first, turning an opaque crash into a readable one.
//

import Foundation

enum CrashDiagnostics {
    /// Installs the uncaught Objective-C exception handler. Call once on
    /// launch, before any UI is built.
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(24).joined(separator: "\n")
            NSLog(
                "[Stillhabit] Uncaught exception %@: %@\n%@",
                exception.name.rawValue,
                exception.reason ?? "no reason",
                symbols
            )
        }
    }
}
