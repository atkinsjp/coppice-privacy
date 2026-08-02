//
//  PersistentModel+Alive.swift
//  Stillhabit
//
//  SwiftData models are backed by Core Data objects. Reading a property of a
//  model that has been deleted from its context raises an Objective-C
//  `NSObjectInaccessibleException` ("CoreData could not fulfill a fault"),
//  which is *not* a Swift error — it cannot be caught with `do/catch` and
//  terminates the process with SIGABRT.
//
//  SwiftUI keeps deleted rows alive for the duration of their removal
//  transition, and timers/tasks captured by those rows can still fire during
//  that window, so every read of a model that might have been deleted has to
//  be guarded first.
//

import Foundation
import SwiftData

extension PersistentModel {
    /// Whether this model is still safe to read from.
    ///
    /// False once the object has been deleted from its context (or detached
    /// from every context), which is exactly when touching its properties
    /// would raise `NSObjectInaccessibleException` and abort the app.
    var isAlive: Bool {
        !isDeleted && modelContext != nil
    }
}
