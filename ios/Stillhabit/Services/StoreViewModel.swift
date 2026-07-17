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

    init() {
        guard Purchases.isConfigured else { return }
        Task { await listenForUpdates() }
        Task { await fetchOfferings() }
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
