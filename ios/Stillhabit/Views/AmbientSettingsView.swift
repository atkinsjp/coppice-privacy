//
//  AmbientSettingsView.swift
//  Stillhabit
//
//  A small, quiet settings menu anchored to the ambient sound button.
//  Choose a soundscape and adjust its volume independently from the
//  system volume.
//

import SwiftUI

struct AmbientSettingsView: View {
    let player: AmbientSoundPlayer

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

    private var sliderAccent: Color {
        player.current == .off
            ? DesignSystem.Colors.textSecondary.opacity(0.5)
            : player.current.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AMBIENT SOUND")
                .font(DesignSystem.Typography.overline)
                .tracking(1.6)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(AmbientSound.allCases, id: \.self) { sound in
                    soundChoice(sound)
                }
            }

            volumeRow

            loopRow
        }
        .padding(.horizontal, DesignSystem.Layout.horizontalPadding)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Sound choice

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
                    .foregroundStyle(
                        isSelected ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary
                    )

                Text(shortName(for: sound))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected ? DesignSystem.Colors.onAccent : DesignSystem.Colors.textSecondary
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
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
        case .off: return "Off"
        case .forest: return "Forest"
        case .rain: return "Rain"
        }
    }

    // MARK: - Volume

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

    // MARK: - Loop

    private var loopRow: some View {
        Toggle(isOn: loopBinding) {
            HStack(spacing: 8) {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text("Loop continuously")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(sliderAccent)
        .disabled(player.current == .off)
        .opacity(player.current == .off ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: player.current)
        .accessibilityLabel("Loop ambient sound continuously")
        .accessibilityHint("When off, the soundscape plays once and then falls silent")
    }
}

#Preview {
    AmbientSettingsView(player: AmbientSoundPlayer())
}
