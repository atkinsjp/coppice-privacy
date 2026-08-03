//
//  StoreViewModel.swift
//  Stillhabit
//
//  Central subscription state, backed by RevenueCat.
//

import Foundation
import Observation
import RevenueCat

@Observable
final class StoreViewModel {
    /// RevenueCat entitlement that unlocks Stillhabit Pro.
    static let entitlementID = "StillHabit Pro"
    /// Active habits allowed before the paywall appears.
    static let freeHabitLimit = 3

    var offerings: Offerings?
    var isPremium = false
    var isLoading = false
    var isPurchasing = false
    var errorMessage: String?

    /// Set from anywhere in the app to ask the root view to raise the paywall.
    ///
    /// The paywall is a `fullScreenCover` owned by `ContentView`, not a sheet
    /// owned by `TodayView` — two presentations racing on the same view is the
    /// exact pattern that aborts this app, so the lock lives one level up and
    /// is requested through this flag rather than presented locally.
    var isPaywallRequested = false

    init() {
        guard Purchases.isConfigured else { return }
        Task { await listenForUpdates() }
        Task { await fetchOfferings() }
    }

    /// Whether every Pro feature is open right now.
    ///
    /// True for paying subscribers **and** for anyone inside the 72-hour,
    /// no-card-required grace window that starts at first launch. Every
    /// premium gate in the app reads this rather than `isPremium`, so the
    /// paywall never interrupts a brand-new user.
    var hasFullAccess: Bool {
        isPremium || GracePeriod.isActive
    }

    /// True while access is granted by the local grace period rather than by
    /// a purchase — used to show the quiet countdown in Settings.
    var isGracePeriodActive: Bool {
        !isPremium && GracePeriod.isActive
    }

    var monthlyPackage: Package? {
        offerings?.current?.availablePackages.first { $0.packageType == .monthly }
    }

    var yearlyPackage: Package? {
        offerings?.current?.availablePackages.first { $0.packageType == .annual }
    }

    private func listenForUpdates() async {
        for await info in Purchases.shared.customerInfoStream {
            isPremium = info.entitlements[Self.entitlementID]?.isActive == true
        }
    }

    func fetchOfferings() async {
        guard Purchases.isConfigured else { return }
        isLoading = true
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func purchase(package: Package) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                isPremium = result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
            }
        } catch ErrorCode.purchaseCancelledError {
            // The user changed their mind — not an error.
        } catch ErrorCode.paymentPendingError {
            // Awaiting approval / extra auth — not a failure.
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    func restore() async {
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPremium = info.entitlements[Self.entitlementID]?.isActive == true
            if !isPremium {
                errorMessage = "No previous purchases were found for this account."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
