//
//  StillhabitApp.swift
//  Stillhabit
//

import SwiftUI
import SwiftData
import UserNotifications
import RevenueCat

@main
struct StillhabitApp: App {
    private let container: ModelContainer = SharedStore.makeContainer()
    /// Keeps reminder banners visible while the app is in the foreground.
    private let notificationDelegate = ReminderPresentationDelegate()
    @State private var store: StoreViewModel

    init() {
        CrashDiagnostics.install()
        #if DEBUG
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_TEST_API_KEY)
        #else
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY)
        #endif
        _store = State(initialValue: StoreViewModel())
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
