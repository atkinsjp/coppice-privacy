//
//  SettingsView.swift
//  StillHabitCalmHabitTracker
//
//  The utilities sheet: appearance, list order, ambient sound, subscription,
//  support, and the one irreversible action. Built from the same quiet card
//  language as the rest of the app and sitting directly on the drifting
//  earthy backdrop, so opening it feels like turning a page rather than
//  entering a different application.
//

import SwiftUI
import SwiftData
import UserNotifications
import AuthenticationServices

struct SettingsView: View {
    /// The Today view's ambient player, so soundscape changes are heard live.
    let player: AmbientSoundPlayer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(StoreViewModel.self) private var store
    @Environment(AccountService.self) private var account
    @Environment(AppLockService.self) private var appLock
    @Environment(\.colorScheme) private var colorScheme

    /// Theme override. Read here and applied at the window root.
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    /// Today-list order, shared with `TodayView`.
    @AppStorage("stillhabit.sortMode") private var sortModeRaw: String = HabitSortMode.manual.rawValue

    @State private var isConfirmingErase = false
    /// Shown when Face ID lock can't be enabled because the device offers
    /// neither biometrics nor a passcode.
    @State private var isLockUnavailableShown = false
    /// Set after a successful erase so the confirmation reads as an outcome
    /// rather than leaving the user wondering whether anything happened.
    @State private var didErase = false
    /// Re-read on appear so the grace countdown is always current without a
    /// running timer.
    @State private var countdown: String?

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var sortMode: HabitSortMode {
        HabitSortMode(rawValue: sortModeRaw) ?? .manual
    }

    private let feedbackAddress = "support@atkinsmedia.io"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                appearanceSection
                orderSection
                ambientSection
                subscriptionSection
                accountSection
                syncSection
                privacySection
                supportSection
                legalSection
                eraseSection

                if let countdown {
                    graceFootnote(countdown)
                }

                versionLine
            }
            .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
            .padding(.top, 30)
            .padding(.bottom, 44)
        }
        .background {
            WavyBackgroundView()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .presentationBackground(DesignSystem.Colors.background)
        .alert("Are you sure?", isPresented: $isConfirmingErase) {
            Button("Erase Everything", role: .destructive) { eraseAllData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes every habit, streak, note, and reminder stored on this device. It cannot be undone.")
        }
        .onAppear {
            countdown = GracePeriod.countdownLabel
        }
    }

    // MARK: - Chrome

    private var closeButton: some View {
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
        .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.textSecondary))
        .padding(.top, 16)
        .padding(.trailing, DesignSystem.Layout.horizontalPadding - 4)
        .accessibilityLabel("Close settings")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STILLHABIT")
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Settings")
                .font(DesignSystem.Typography.largeHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.trailing, 44)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        settingsGroup("APPEARANCE") {
            HStack(spacing: 8) {
                ForEach(AppearanceMode.allCases) { mode in
                    appearanceChoice(mode)
                }
            }

            Text(appearanceFootnote)
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .animation(.easeInOut(duration: 0.2), value: appearance)
        }
    }

    private var appearanceFootnote: String {
        switch appearance {
        case .system: return "Following your device setting."
        case .light:  return "Always warm ivory, even at night."
        case .dark:   return "Always deep charcoal, even at noon."
        }
    }

    private func appearanceChoice(_ mode: AppearanceMode) -> some View {
        let isSelected = appearance == mode

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appearanceRaw = mode.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 15, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                isSelected ? DesignSystem.Colors.sage : DesignSystem.Colors.background,
                in: RoundedRectangle(cornerRadius: DesignSystem.Layout.fieldCornerRadius)
            )
        }
        .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.sage))
        .accessibilityLabel("\(mode.label) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - List order

    private var orderSection: some View {
        settingsGroup("TODAY'S ORDER") {
            VStack(spacing: 4) {
                ForEach(HabitSortMode.allCases) { mode in
                    orderRow(mode)
                }
            }
        }
    }

    private func orderRow(_ mode: HabitSortMode) -> some View {
        let isSelected = sortMode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                sortModeRaw = mode.rawValue
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? DesignSystem.Colors.sage : DesignSystem.Colors.textSecondary)
                    .frame(width: 20)

                Text(mode.label)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.sage)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            .frame(height: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.stillQuietPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Ambient sound

    private var ambientSection: some View {
        settingsGroup("AMBIENT SOUND") {
            HStack(spacing: 8) {
                ForEach(AmbientSound.allCases, id: \.self) { sound in
                    soundChoice(sound)
                }
            }

            volumeRow
            loopRow
        }
    }

    private func soundChoice(_ sound: AmbientSound) -> some View {
        let isSelected = player.current == sound

        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                player.select(sound)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: sound.icon)
                    .font(.system(size: 15, weight: .medium))
                Text(shortName(for: sound))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                isSelected ? sound.accent : DesignSystem.Colors.background,
                in: RoundedRectangle(cornerRadius: DesignSystem.Layout.fieldCornerRadius)
            )
        }
        .buttonStyle(.stillTactileWave(accent: sound.accent))
        .accessibilityLabel(sound.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shortName(for sound: AmbientSound) -> String {
        switch sound {
        case .off:    return "Off"
        case .forest: return "Forest"
        case .rain:   return "Rain"
        }
    }

    private var sliderAccent: Color {
        player.current == .off
            ? DesignSystem.Colors.textSecondary.opacity(0.5)
            : player.current.accent
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(player.volume) },
            set: { player.volume = Float($0) }
        )
    }

    private var loopBinding: Binding<Bool> {
        Binding(
            get: { player.isLoopingEnabled },
            set: { player.isLoopingEnabled = $0 }
        )
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Slider(value: volumeBinding, in: 0...1)
                .tint(sliderAccent)
                .controlSize(.mini)
                .disabled(player.current == .off)
                .accessibilityLabel("Ambient sound volume")
                .accessibilityValue("\(Int(player.volume * 100)) percent")

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .opacity(player.current == .off ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: player.current)
    }

    private var loopRow: some View {
        Toggle(isOn: loopBinding) {
            Text("Loop continuously")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(sliderAccent)
        .disabled(player.current == .off)
        .opacity(player.current == .off ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: player.current)
        .accessibilityHint("When off, the soundscape plays once and then falls silent")
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        settingsGroup("SUBSCRIPTION") {
            HStack(spacing: 10) {
                Circle()
                    .fill(store.hasFullAccess ? DesignSystem.Colors.sage : DesignSystem.Colors.textSecondary.opacity(0.4))
                    .frame(width: 7, height: 7)

                Text(accessStatusLine)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer(minLength: 0)
            }

            Divider().overlay(DesignSystem.Colors.textSecondary.opacity(0.15))

            actionRow(title: "Manage Subscription", icon: "creditcard") {
                open("https://apps.apple.com/account/subscriptions")
            }

            actionRow(title: "Restore Purchases", icon: "arrow.clockwise") {
                Task { await store.restore() }
            }
        }
    }

    private var accessStatusLine: String {
        if store.isPremium { return "StillHabitCalmHabitTracker Pro — active" }
        if GracePeriod.isActive { return "Everything unlocked for now" }
        return "Free — three habits"
    }

    // MARK: - Account

    /// Sign in with Apple — the app's one identity anchor. Signing in keeps a
    /// stable Apple identifier so future Pro restoration and trial tracking
    /// can resolve to the same person across reinstalls.
    private var accountSection: some View {
        settingsGroup("ACCOUNT") {
            if account.isSignedIn {
                signedInRow
                Divider().overlay(DesignSystem.Colors.textSecondary.opacity(0.15))
                actionRow(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right") {
                    account.signOut()
                }
                Text("Signing out removes Apple sign-in from StillHabitCalmHabitTracker on this device only.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    account.makeRequest(request)
                } onCompletion: { result in
                    account.handleAuthorization(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .clipShape(.rect(cornerRadius: DesignSystem.Layout.fieldCornerRadius))

                Text("Keeps your access with you if you reinstall or switch devices, without an email or password.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var signedInRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(DesignSystem.Colors.sage)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                if let email = account.email, email != account.displayName {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sync

    private var syncSection: some View {
        settingsGroup("ICLOUD SYNC") {
            HStack(spacing: 10) {
                Circle()
                    .fill(SharedStore.isCloudKitEnabled ? DesignSystem.Colors.sage : DesignSystem.Colors.textSecondary.opacity(0.4))
                    .frame(width: 7, height: 7)

                Text(syncStatusLine)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer(minLength: 0)
            }

            Text(syncFootnote)
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var syncStatusLine: String {
        SharedStore.isCloudKitEnabled ? "Synced to iCloud" : "On this device only"
    }

    private var syncFootnote: String {
        if SharedStore.isCloudKitEnabled {
            return "Your habits sync across your devices through your iCloud account. Changes appear within a few moments."
        }
        return "Sign in to iCloud on this device to sync your habits across your iPhone and iPad."
    }

    // MARK: - Privacy

    /// Optional Face ID lock. Habits stay on-device regardless — this only
    /// hides them from whoever picks up the phone next.
    private var privacySection: some View {
        settingsGroup("PRIVACY") {
            HStack(spacing: 12) {
                Image(systemName: "faceid")
                    .font(.system(size: 17))
                    .foregroundStyle(DesignSystem.Colors.sage)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Face ID Lock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(appLock.isLockEnabled ? "On — habits hide when you leave the app" : "Off")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .animation(.easeInOut(duration: 0.2), value: appLock.isLockEnabled)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { appLock.isLockEnabled },
                    set: { newValue in
                        guard newValue != appLock.isLockEnabled else { return }
                        Task {
                            let confirmed = await appLock.setLockEnabled(newValue)
                            if !confirmed {
                                isLockUnavailableShown = true
                            }
                        }
                    }
                ))
                .labelsHidden()
                .tint(DesignSystem.Colors.sage)
            }
            .accessibilityElement(children: .combine)

            Text("When on, leaving Stillhabit hides every habit behind a quiet screen until your face (or device passcode) unlocks it.")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .alert("Face ID unavailable", isPresented: $isLockUnavailableShown) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This device has no biometric unlock or passcode set up, so the lock can't be turned on.")
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        settingsGroup("SUPPORT") {
            actionRow(title: "Send Feedback", icon: "envelope") {
                openFeedbackMail()
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        settingsGroup("LEGAL") {
            actionRow(title: "Privacy Policy", icon: "hand.raised") {
                open("https://atkinsjp.github.io/rork-calm-habit-tracker/website/privacy-policy.html")
            }
            actionRow(title: "Terms of Service", icon: "doc.text") {
                open("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
            }
        }
    }

    // MARK: - Erase

    private var eraseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isConfirmingErase = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                    Text("Erase All Habits & Data")
                        .font(.system(size: 15, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DesignSystem.Colors.terracotta)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                        .strokeBorder(DesignSystem.Colors.terracotta.opacity(0.28), lineWidth: 0.5)
                }
                .softShadow()
            }
            .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.terracotta))
            .accessibilityHint("Asks for confirmation before permanently deleting everything")

            Text("Erasing also removes synced data from iCloud on this device. It cannot be undone.")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Footnotes

    /// The quiet grace-period countdown, in muted taupe, at the very bottom.
    private func graceFootnote(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "hourglass")
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .accessibilityLabel("\(text). No card required.")
    }

    private var versionLine: some View {
        Text(didErase ? "A clean slate." : "Small things, done gently, every day.")
            .font(.system(size: 11))
            .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.4), value: didErase)
    }

    // MARK: - Building blocks

    /// A titled card of related controls — the app's one settings container.
    @ViewBuilder
    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.card, in: .rect(cornerRadius: DesignSystem.Layout.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                    .strokeBorder(DesignSystem.Colors.textSecondary.opacity(0.12), lineWidth: 0.5)
            }
            .softShadow()
        }
    }

    private func actionRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.6))
            }
            .frame(height: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.stillQuietPress)
    }

    // MARK: - Actions

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        openURL(url)
    }

    /// Opens the system mail composer pre-addressed with a calm subject line.
    private func openFeedbackMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "StillHabitCalmHabitTracker feedback")
        ]
        guard let url = components.url else { return }
        openURL(url)
    }

    /// Erases every habit and restarts the local grace window.
    ///
    /// Order matters: pending notifications are dropped first (they reference
    /// habit IDs that are about to vanish), then the store is emptied in one
    /// batch delete and saved immediately, so no view is left holding a
    /// deleted SwiftData object — reading one raises
    /// `NSObjectInaccessibleException`, which aborts the process. The sheet
    /// closes a beat later, after the write has settled.
    private func eraseAllData() {
        CrashDiagnostics.note("erase all data")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        do {
            try modelContext.delete(model: Habit.self)
            try modelContext.save()
        } catch {
            print("SettingsView: erase failed — \(error.localizedDescription)")
        }

        GracePeriod.reset()
        countdown = GracePeriod.countdownLabel
        SharedStore.notifyWidgets()

        withAnimation(.easeInOut(duration: 0.35)) {
            didErase = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(650))
            dismiss()
        }
    }
}

#Preview {
    SettingsView(player: AmbientSoundPlayer())
        .modelContainer(for: Habit.self, inMemory: true)
        .environment(StoreViewModel())
}
