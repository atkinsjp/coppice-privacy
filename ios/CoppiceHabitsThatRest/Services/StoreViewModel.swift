//
//  StoreViewModel.swift
//  CoppiceHabitsThatRest
//
//  Central subscription state, backed by RevenueCat.
//

import Foundation
import Observation
import RevenueCat

@Observable
final class StoreViewModel {
    /// RevenueCat entitlement that unlocks CoppiceHabitsThatRest Pro.
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

    /// Incremented exactly once each time a purchase completes and the
    /// entitlement turns active. The Today view watches this to play its
    /// quiet celebration.
    ///
    /// A counter rather than reusing `isPremium`: the customer-info stream
    /// also flips `isPremium` to true a moment after every launch for
    /// existing subscribers, and celebrating a cold start would be absurd.
    /// This only moves inside `purchase(package:)`, on genuine success.
    var purchaseCelebrationTick = 0

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

    /// Monthly plan. Matches by package type first, then falls back to the
    /// subscription period — a package created with a custom identifier in
    /// RevenueCat still resolves instead of silently going nil.
    var monthlyPackage: Package? {
        guard let packages = offerings?.current?.availablePackages else { return nil }
        return packages.first { $0.packageType == .monthly }
            ?? packages.first { $0.storeProduct.subscriptionPeriod?.unit == .month }
    }

    /// Yearly plan. Same matching strategy as `monthlyPackage`.
    var yearlyPackage: Package? {
        guard let packages = offerings?.current?.availablePackages else { return nil }
        return packages.first { $0.packageType == .annual }
            ?? packages.first { $0.storeProduct.subscriptionPeriod?.unit == .year }
    }

    /// True when offerings loaded but neither plan could be resolved — the
    /// paywall uses this to surface a hint instead of a silently dead button.
    var packagesUnavailable: Bool {
        !isLoading && offerings != nil
            && monthlyPackage == nil
            && yearlyPackage == nil
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
            CrashDiagnostics.note("offerings: \(offerings?.current?.availablePackages.count ?? 0) packages")
        } catch {
            CrashDiagnostics.note("offerings failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func purchase(package: Package) async {
        guard !isPurchasing else { return }
        CrashDiagnostics.note("purchase: \(package.storeProduct.productIdentifier)")
        isPurchasing = true
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                let wasPremium = isPremium
                isPremium = result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
                if isPremium && !wasPremium {
                    purchaseCelebrationTick += 1
                }
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
