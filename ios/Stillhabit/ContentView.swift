//
//  ContentView.swift
//  Stillhabit
//

import SwiftUI
import SwiftData

/// Root of the app: one focused Today view.
/// No tab bars, no floating buttons — just today.
struct ContentView: View {
    var body: some View {
        TodayView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
}
