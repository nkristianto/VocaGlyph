import SwiftUI

/// Recording Setup section: global shortcut, dictation language, and microphone selection.
struct RecordingSetupSection: View {
    @Bindable var microphoneService: MicrophoneService

    @AppStorage(UserDefaults.customShortcutKeyCodeKey) private var customShortcutKeyCode: Int = UserDefaults.defaultShortcutKeyCode
    @AppStorage(UserDefaults.customShortcutModifiersKey) private var customShortcutModifiersRaw: Double = Double(UserDefaults.defaultShortcutModifiers)
    @AppStorage("dictationLanguage") private var dictationLanguage: String = "Auto-Detect"

    private var currentShortcutDisplay: String {
        let flags = CGEventFlags(rawValue: UInt64(customShortcutModifiersRaw))
        return ShortcutDisplayHelper.displayString(keyCode: CGKeyCode(customShortcutKeyCode), flags: flags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Recording Setup")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "mic")
                    .foregroundStyle(Theme.navy)
            }

            VStack(spacing: 0) {
                // Global Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global Shortcut")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Click the shortcut to record a new one")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    ShortcutRecorderButton(
                        displayLabel: currentShortcutDisplay,
                        onShortcutRecorded: { keyCode, modifiers in
                            Logger.shared.debug("Settings: Recorded new shortcut keyCode=\(keyCode) modifiers=\(modifiers.rawValue)")
                            customShortcutKeyCode = Int(keyCode)
                            customShortcutModifiersRaw = Double(modifiers.rawValue)
                        },
                        onReset: {
                            Logger.shared.debug("Settings: Reset shortcut to default")
                            customShortcutKeyCode = UserDefaults.defaultShortcutKeyCode
                            customShortcutModifiersRaw = Double(UserDefaults.defaultShortcutModifiers)
                        }
                    )
                }
                .padding(16)

                Divider().background(Theme.textMuted.opacity(0.1))

                // Dictation Language
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dictation Language")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text(dictationLanguage == "Auto-Detect" ? "Whisper detects language automatically" : "Primary language for transcription")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Menu {
                        Button("Auto-Detect") {
                            Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'Auto-Detect'")
                            dictationLanguage = "Auto-Detect"
                        }
                        Divider()
                        Button("English (US)") {
                            Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'English (US)'")
                            dictationLanguage = "English (US)"
                        }
                        Button("Spanish (ES)") {
                            Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'Spanish (ES)'")
                            dictationLanguage = "Spanish (ES)"
                        }
                        Button("French (FR)") {
                            Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'French (FR)'")
                            dictationLanguage = "French (FR)"
                        }
                        Button("German (DE)") {
                            Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'German (DE)'")
                            dictationLanguage = "German (DE)"
                        }
                        Button("Indonesian (ID)") {
                            Logger.shared.debug("Settings: Changed Dictation Language from '\(dictationLanguage)' to 'Indonesian (ID)'")
                            dictationLanguage = "Indonesian (ID)"
                        }
                    } label: {
                        HStack {
                            Text(dictationLanguage)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.navy)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 140)
                }
                .padding(16)

                Divider().background(Theme.textMuted.opacity(0.1))

                // Microphone Selection
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Input device used for voice recording")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Menu {
                        ForEach(microphoneService.availableInputs) { device in
                            Button(device.name) {
                                Logger.shared.debug("Settings: Changed Microphone to '\(device.name)'")
                                microphoneService.select(device)
                            }
                            if device == .systemDefault && microphoneService.availableInputs.count > 1 {
                                Divider()
                            }
                        }
                    } label: {
                        HStack {
                            Text(microphoneService.selectedDevice.name)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.navy)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 160)
                }
                .padding(16)
            }
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
            )
        }
    }
}
