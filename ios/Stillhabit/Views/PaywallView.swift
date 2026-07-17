//
//  PaywallView.swift
//  Stillhabit
//
//  Shown only when a fourth habit is attempted.
//  Calm, honest, and clear about the 7-day free trial.
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(StoreViewModel.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Plan {
        case monthly
        case yearly
    }

    @State private var selectedPlan: Plan = .yearly
    @State private var isPreviewingPalette = false

    private var monthlyPrice: String {
        store.monthlyPackage?.storeProduct.localizedPriceString ?? "$2.99"
    }

    private var yearlyPrice: String {
        store.yearlyPackage?.storeProduct.localizedPriceString ?? "$14.99"
    }

    private var selectedPackage: Package? {
        selectedPlan == .monthly ? store.monthlyPackage : store.yearlyPackage
    }

    private var ctaTitle: String {
        selectedPlan == .yearly ? "Start my 7-day free trial" : "Continue with Monthly"
    }

    private var ctaFootnote: String {
        selectedPlan == .yearly
            ? "7 days free, then \(yearlyPrice) per year. Cancel anytime."
            : "\(monthlyPrice) per month. Cancel anytime."
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    VStack(spacing: 12) {
                        planCard(
                            plan: .monthly,
                            title: "Monthly",
                            price: monthlyPrice,
                            period: "per month",
                            badge: nil
                        )
                        planCard(
                            plan: .yearly,
                            title: "Yearly",
                            price: yearlyPrice,
                            period: "per year",
                            badge: "7-DAY FREE TRIAL"
                        )
                    }

                    ctaSection

                    palettePreview

                    restoreLink
                }
                .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(DesignSystem.Colors.card, in: Circle())
                    .softShadow()
            }
            .frame(width: 44, height: 44)
            .padding(.top, 16)
            .padding(.trailing, DesignSystem.Layout.horizontalPadding - 4)
            .accessibilityLabel("Close")
        }
        .presentationBackground(DesignSystem.Colors.background)
        .alert("Something went quiet", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.isPremium) { _, isPremium in
            if isPremium { dismiss() }
        }
        .task {
            if store.offerings == nil {
                await store.fetchOfferings()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DesignSystem.Colors.sage)

            Text("Space for everything that matters.")
                .font(DesignSystem.Typography.largeHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.trailing, 36)

            Text("Stillhabit Pro lifts the three-habit limit and opens the full muted palette.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Plan cards

    private func planCard(plan: Plan, title: String, price: String, period: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(DesignSystem.Typography.label)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(DesignSystem.Colors.onAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DesignSystem.Colors.sage, in: Capsule())
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(price)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text(period)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.sage : DesignSystem.Colors.textSecondary.opacity(0.5))
            }
            .padding(20)
            .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .strokeBorder(
                        isSelected ? DesignSystem.Colors.sage.opacity(0.7) : Color.clear,
                        lineWidth: 1.5
                    )
            }
            .softShadow()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(title), \(price) \(period)\(badge != nil ? ", includes 7 day free trial" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button {
                guard let package = selectedPackage else { return }
                Task { await store.purchase(package: package) }
            } label: {
                Group {
                    if store.isPurchasing {
                        ProgressView()
                            .tint(DesignSystem.Colors.onAccent)
                    } else {
                        Text(ctaTitle)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.onAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(DesignSystem.Colors.sage, in: Capsule())
                .softShadow()
            }
            .disabled(store.isPurchasing || selectedPackage == nil)
            .opacity(selectedPackage == nil && !store.isLoading ? 0.5 : 1)

            Text(ctaFootnote)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPlan)
    }

    // MARK: - Premium palette preview

    private var palettePreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $isPreviewingPalette.animation(.spring(response: 0.35, dampingFraction: 0.7))) {
                Text("Preview the Pro palette")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .tint(DesignSystem.Colors.sage)

            if isPreviewingPalette {
                HStack(spacing: 14) {
                    ForEach(DesignSystem.premiumPalette) { habitColor in
                        Circle()
                            .fill(habitColor.color)
                            .frame(width: 30, height: 30)
                            .accessibilityLabel(habitColor.name)
                    }
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .background(DesignSystem.Colors.card.opacity(0.6), in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
    }

    // MARK: - Restore

    private var restoreLink: some View {
        Button {
            Task { await store.restore() }
        } label: {
            Text("Restore Purchases")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .underline()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}

#Preview {
    PaywallView()
        .environment(StoreViewModel())
}
