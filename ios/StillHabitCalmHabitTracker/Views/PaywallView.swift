//
//  PaywallView.swift
//  StillHabitCalmHabitTracker
//
//  The moment the 72-hour grace window closes.
//
//  Editorial rather than promotional: a wide margin of quiet at the top, one
//  serif headline, an italic line of context, and a left-aligned column of
//  what the user has been living with for three days. Loss is stated once,
//  gently, and never with red crosses — the sage checkmarks say "this is
//  yours, keep it" instead of "you failed".
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    /// When true, a quiet close control sits in the top-left corner and the
    /// user may return to the free tier (three habits, the base palette) and
    /// keep reading their history instead of subscribing. When false the
    /// screen is a hard lock with no way out but a choice.
    var allowsDismiss: Bool = true

    @Environment(StoreViewModel.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Plan {
        case monthly
        case yearly
    }

    @State private var selectedPlan: Plan = .yearly
    /// Drives the staggered entrance of the headline and the value column.
    @State private var hasSettled = false

    private let termsURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    private let privacyURL = "https://atkinsjp.github.io/coppice-privacy/website/privacy-policy.html"

    // MARK: - Pricing

    private var monthlyPrice: String {
        store.monthlyPackage?.storeProduct.localizedPriceString ?? "$4.99"
    }

    private var yearlyPrice: String {
        store.yearlyPackage?.storeProduct.localizedPriceString ?? "$29.99"
    }

    private var selectedPackage: Package? {
        selectedPlan == .monthly ? store.monthlyPackage : store.yearlyPackage
    }

    /// How much the annual plan saves against twelve monthly charges. Derived
    /// from live StoreKit prices when offerings have loaded, with the
    /// $4.99 / $29.99 fallback so the pill never reads as empty.
    private var savingsLabel: String? {
        let monthly = store.monthlyPackage?.storeProduct.price ?? Decimal(4.99)
        let yearly = store.yearlyPackage?.storeProduct.price ?? Decimal(29.99)
        let twelveMonths = monthly * 12
        guard twelveMonths > 0, twelveMonths > yearly else { return nil }
        let ratio = (twelveMonths - yearly) / twelveMonths
        let percent = Int((NSDecimalNumber(decimal: ratio).doubleValue * 100).rounded())
        guard percent >= 5 else { return nil }
        return "Save \(percent)%"
    }

    private var renewalLine: String {
        selectedPlan == .yearly
            ? "\(yearlyPrice) per year, billed to your Apple Account. Renews until cancelled."
            : "\(monthlyPrice) per month, billed to your Apple Account. Renews until cancelled."
    }

    /// What the user will lose when the window closes — stated as things worth
    /// keeping rather than as punishments.
    private let keepsakes: [String] = [
        "Preserve your 90-day completion history",
        "Keep your custom habit schedules and \u{201C}Why\u{201D} anchors",
        "Maintain access to the \u{2018}Coppice Moment\u{2019} sensory rewards",
        "Unlimited active habits",
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            WavyBackgroundView()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The editorial margin: a deliberate field of nothing
                    // before the headline, like the opening page of a book.
                    Spacer(minLength: 92)
                        .frame(height: 92)

                    masthead

                    headline
                        .padding(.top, 18)

                    subheadline
                        .padding(.top, 14)

                    keepsakeColumn
                        .padding(.top, 38)

                    planCards
                        .padding(.top, 40)

                    ctaSection
                        .padding(.top, 24)

                    legalFooter
                        .padding(.top, 18)
                }
                .padding(.horizontal, DesignSystem.Layout.horizontalPadding + 4)
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topLeading) {
            if allowsDismiss {
                closeButton
            }
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
        .onAppear {
            guard !reduceMotion else {
                hasSettled = true
                return
            }
            withAnimation(.easeOut(duration: 0.7)) {
                hasSettled = true
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    // MARK: - Chrome

    /// Deliberately in the top-*left* and deliberately faint: leaving is
    /// possible, but it is not the thing the eye lands on.
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(DesignSystem.Colors.card.opacity(0.7), in: Circle())
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.stillQuietPress)
        .padding(.top, 12)
        .padding(.leading, DesignSystem.Layout.horizontalPadding - 4)
        .accessibilityLabel("Continue with limited access")
        .accessibilityHint("Keeps your history readable with up to three active habits")
    }

    // MARK: - Header

    /// A single hairline-thin overline, the only ornament above the headline.
    private var masthead: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(DesignSystem.Colors.sage)
                .frame(width: 22, height: 1)

            Text("STILLHABIT PRO")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(DesignSystem.Colors.sage)
        }
        .opacity(hasSettled ? 1 : 0)
    }

    /// The one loud thing on the page. Serif, tightly leaded, three words to a
    /// line so it reads as a pull quote rather than a sales headline.
    private var headline: some View {
        Text("Keep your quiet space.")
            .font(.system(size: 40, weight: .bold, design: .serif))
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .lineSpacing(-2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 24)
            .opacity(hasSettled ? 1 : 0)
            .offset(y: hasSettled ? 0 : 10)
    }

    private var subheadline: some View {
        Text("Your 3-day trial has ended. Subscribe to preserve your streaks and keep your routines intact.")
            .font(.system(size: 15, weight: .regular).italic())
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 16)
            .opacity(hasSettled ? 1 : 0)
    }

    // MARK: - What stays with you

    private var keepsakeColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WHAT STAYS WITH YOU")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.85))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(keepsakes.enumerated()), id: \.offset) { index, line in
                    keepsakeRow(line, index: index)
                }
            }
        }
    }

    private func keepsakeRow(_ text: String, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.sage)
                .frame(width: 12)

            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(hasSettled ? 1 : 0)
        .offset(x: hasSettled ? 0 : -6)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.12 + Double(index) * 0.07),
            value: hasSettled
        )
    }

    // MARK: - Plans

    private var planCards: some View {
        VStack(spacing: 10) {
            planCard(
                plan: .yearly,
                title: "Yearly",
                price: yearlyPrice,
                period: "per year",
                badge: "BEST VALUE"
            )
            planCard(
                plan: .monthly,
                title: "Monthly",
                price: monthlyPrice,
                period: "per month",
                badge: nil
            )
        }
    }

    private func planCard(plan: Plan, title: String, price: String, period: String, badge: String?) -> some View {
        let isSelected = selectedPlan == plan
        let isFeatured = plan == .yearly

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(DesignSystem.Colors.onAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(DesignSystem.Colors.sage, in: Capsule())
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(price)
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        Text(period)
                            .font(.system(size: 13))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    if isFeatured, let savingsLabel {
                        Text(savingsLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.sage)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(
                        isSelected
                            ? DesignSystem.Colors.sage
                            : DesignSystem.Colors.textSecondary.opacity(0.45)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .fill(DesignSystem.Colors.card)
                    .overlay {
                        // A soft sage tint marks the active card, so selection
                        // reads even before the border does.
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                            .fill(DesignSystem.Colors.sage.opacity(isSelected ? 0.09 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .strokeBorder(
                        isSelected
                            ? DesignSystem.Colors.sage
                            : (isFeatured
                                ? DesignSystem.Colors.sage.opacity(0.45)
                                : DesignSystem.Colors.textSecondary.opacity(0.15)),
                        lineWidth: isSelected ? 1.75 : 0.75
                    )
            }
            .softShadow()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(title), \(price) \(period)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Action

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                guard let package = selectedPackage else { return }
                Task { await store.purchase(package: package) }
            } label: {
                Group {
                    if store.isPurchasing {
                        ProgressView()
                            .tint(DesignSystem.Colors.onAccent)
                    } else {
                        Text("Subscribe to Keep Access")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSystem.Colors.onAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(DesignSystem.Colors.sage, in: Capsule())
                .softShadow()
            }
            .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.onAccent))
            .disabled(store.isPurchasing || selectedPackage == nil)
            .opacity(selectedPackage == nil && !store.isLoading ? 0.55 : 1)

            Text(renewalLine)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: selectedPlan)
        }
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        HStack(spacing: 7) {
            Spacer(minLength: 0)

            legalLink("Restore Purchases") {
                Task { await store.restore() }
            }
            footerDot
            legalLink("Terms of Service") { open(termsURL) }
            footerDot
            legalLink("Privacy Policy") { open(privacyURL) }

            Spacer(minLength: 0)
        }
    }

    private var footerDot: some View {
        Text("\u{2022}")
            .font(.system(size: 10))
            .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))
            .accessibilityHidden(true)
    }

    private func legalLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.vertical, 10)
                .contentShape(.rect)
        }
        .buttonStyle(.stillQuietPress)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        openURL(url)
    }
}

#Preview("Dismissible") {
    PaywallView()
        .environment(StoreViewModel())
}

#Preview("Hard lock") {
    PaywallView(allowsDismiss: false)
        .environment(StoreViewModel())
        .preferredColorScheme(.dark)
}
