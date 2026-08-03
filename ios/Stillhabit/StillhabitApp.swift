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
    @State private var store: StoreViewModel

    /// The user's theme override. Applied once here at the window root so
    /// every sheet inherits it too.
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    /// Keeps reminder banners visible while the app is in the foreground.
    ///
    /// `UNUserNotificationCenter.delegate` is a **weak** reference, so the
    /// delegate has to be owned somewhere that outlives every value copy of
    /// this `App` struct — otherwise it can be deallocated and the center left
    /// messaging a dangling object.
    private static let notificationDelegate = ReminderPresentationDelegate()

    init() {
        CrashDiagnostics.install()
        #if DEBUG
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_TEST_API_KEY)
        #else
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY)
        #endif
        _store = State(initialValue: StoreViewModel())
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
    }
}
