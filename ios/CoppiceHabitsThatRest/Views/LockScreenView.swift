//
//  LockScreenView.swift
//  CoppiceHabitsThatRest
//
//  The privacy curtain shown whenever `AppLockService.isLocked`. Sits as a
//  permanent root overlay that fades fully transparent (and stops hit-testing)
//  the moment the lock releases — the same editorial page language as the rest
//  of the app: wavy backdrop, Zen stone emblem, one quiet sentence, one button.
//

import SwiftUI

struct LockScreenView: View {
    /// The lock state machine, owned by the app root.
    let appLock: AppLockService

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 0)

                StillHabitLogoView(size: 96)

                VStack(spacing: 10) {
                    Text("Coppice")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("Your habits are resting.")
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Button {
                    Task { await appLock.authenticate() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Unlock")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(DesignSystem.Colors.onAccent)
                    .padding(.horizontal, 30)
                    .frame(height: 48)
                    .background(DesignSystem.Colors.sage, in: Capsule())
                }
                .buttonStyle(.stillTactileWave(accent: DesignSystem.Colors.sage))
                .accessibilityLabel("Unlock Coppice")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
        }
        .opacity(appLock.isLocked ? 1 : 0)
        .allowsHitTesting(appLock.isLocked)
        .animation(.easeInOut(duration: 0.25), value: appLock.isLocked)
        // Present the system Face ID sheet automatically a beat after the
        // curtain appears, so the common path needs zero taps. Manual taps on
        // Unlock remain available for retries and cancels.
        .task(id: appLock.isLocked) {
            guard appLock.isLocked else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, appLock.isLocked else { return }
            await appLock.authenticate()
        }
    }
}

#Preview {
    LockScreenView(appLock: AppLockService())
}
