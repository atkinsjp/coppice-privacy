//
//  StillhabitApp.swift
//  Stillhabit
//

import SwiftUI
import SwiftData
import RevenueCat

@main
struct StillhabitApp: App {
    private let container: ModelContainer = SharedStore.makeContainer()
    @State private var store: StoreViewModel

    init() {
        #if DEBUG
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_TEST_API_KEY)
        #else
        Purchases.configure(withAPIKey: Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY)
        #endif
        _store = State(initialValue: StoreViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
