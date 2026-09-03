//
//  ContentView.swift
//  CoppiceHabitsThatRest
//

import SwiftUI
import SwiftData

/// Root of the app: one focused Today view, plus the subscription lock.
/// No tab bars, no floating buttons — just today.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(StoreViewModel.self) private var store

    /// True while the paywall is covering the whole screen.
    @State private var isPaywallPresented = false
    /// Set once the user has chosen to keep going without subscribing. Stops
    /// the lock from reappearing for the rest of this launch — it returns on
    /// the next cold start, or the moment they reach for a Pro feature.
    @State private var didChooseFreeTier = false

    var body: some View {
        TodayView()
            // The paywall is presented here rather than from `TodayView` on
            // purpose. `TodayView` already owns a single `.sheet(item:)` for
            // all of its destinations; adding a second presentation to the
            // same view lets two transactions race, which UIKit answers with
            // an uncatchable exception. Owning the cover one level up keeps
            // exactly one presentation per view.
            .fullScreenCover(isPresented: $isPaywallPresented) {
                store.isPaywallRequested = false
                if !store.hasFullAccess {
                    didChooseFreeTier = true
                }
            } content: {
                PaywallView(allowsDismiss: true)
            }
            .onAppear {
                // Stamps the first-ever launch, which opens the 72-hour,
                // no-card-required window in which every Pro feature is
                // unlocked. Idempotent — only the first call ever writes.
                GracePeriod.startIfNeeded()
                raiseLockIfGraceHasEnded()
            }
            .onChange(of: store.isPaywallRequested) { _, isRequested in
                guard isRequested, !isPaywallPresented else { return }
                isPaywallPresented = true
            }
            .onChange(of: store.isPremium) { _, isPremium in
                if isPremium { isPaywallPresented = false }
            }
            .task { await syncReminders() }
    }

    /// Raises the full-screen lock once the local grace window has closed and
    /// nothing has been purchased.
    ///
    /// Only evaluated at launch. Presenting on every foreground return could
    /// land the cover on top of an already-open sheet, so a window that lapses
    /// mid-session is caught either at the next cold start or the instant the
    /// user reaches for a Pro feature — whichever comes first.
    private func raiseLockIfGraceHasEnded() {
        guard !store.hasFullAccess, !didChooseFreeTier, !isPaywallPresented else { return }
        Task {
            // One beat, so the cover animates onto a settled first frame
            // rather than presenting mid-appearance.
            try? await Task.sleep(for: .milliseconds(450))
            guard !store.hasFullAccess, !didChooseFreeTier, !isPaywallPresented else { return }
            CrashDiagnostics.note("paywall lock")
            isPaywallPresented = true
        }
    }

    /// Re-registers every stored habit reminder on launch, so the scheduled
    /// notifications always match the saved times even after a device restore,
    /// a timezone change, or the system dropping pending requests.
    private func syncReminders() async {
        ReminderService.shared.prepareSounds()
        let habits = (try? modelContext.fetch(FetchDescriptor<Habit>())) ?? []
        await ReminderService.shared.syncAll(habits)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Habit.self, inMemory: true)
        .environment(StoreViewModel())
}
