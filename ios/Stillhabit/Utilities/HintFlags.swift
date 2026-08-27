//
//  HintFlags.swift
//  Stillhabit
//
//  UserDefaults keys for one-time education hints. A hint renders until the
//  user performs the gesture it describes once, then retires quietly — the
//  app keeps its resting editorial calm afterward.
//

import Foundation

/// Keys marking one-time hints the user has completed once.
enum HintFlags {
    /// Set the first time a habit card is successfully swiped left to reveal
    /// its edit/rest/delete actions. While unset, the Today list shows a
    /// small line teaching the gesture.
    static let learnedSwipeActions = "stillhabit.learnedSwipeActions"
}
