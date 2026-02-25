import SwiftUI
import Speech

struct OnboardingView: View {
    @State private var permissionsService: PermissionsService
    var onComplete: () -> Void

    // UI state for reactive updates
    @State private var isMicrophoneGranted = false
    @State private var isAccessibilityTrusted = false
    @State private var isSpeechRecognitionGranted = false

    // Timer to poll for external permission changes (like System Settings)
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    init(permissionsService: PermissionsService, onComplete: @escaping () -> Void) {
        self._permissionsService = State(initialValue: permissionsService)
        self.onComplete = onComplete
    }

    var allGranted: Bool {
        return isMicrophoneGranted && isAccessibilityTrusted
    }

    var body: some View {
        VStack(spacing: 14) {
            if let imgUrl = Bundle.module.url(forResource: "appicon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: imgUrl) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding(.top, 16)
            } else {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 50))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 16)
            }

            Text("Welcome to VocaGlyph")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.navy)

            Text("VocaGlyph needs a few permissions to operate correctly.")
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
                .font(.subheadline)
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                // Microphone — required
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required to capture your voice for transcription.",
                    isGranted: isMicrophoneGranted,
                    action: requestMicrophone
                )

                // Accessibility — required
                PermissionRow(
                    icon: "keyboard.fill",
                    title: "Accessibility",
                    description: "Required to type transcribed text into your active app.",
                    isGranted: isAccessibilityTrusted,
                    action: requestAccessibility
                )

                // Speech Recognition — optional, needed for Apple Native engine
                PermissionRow(
                    icon: "waveform.badge.mic",
                    title: "Speech Recognition",
                    description: "Optional. Required when using the Apple Native Speech engine.",
                    isGranted: isSpeechRecognitionGranted,
                    isOptional: true,
                    action: requestSpeechRecognition
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onComplete) {
                Text("Continue")
            }
            .buttonStyle(ContinueButtonStyle())
            .disabled(!allGranted)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 680)
        .background(Color.white)
        .onAppear {
            refreshPermissions()
        }
        .onReceive(timer) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        isMicrophoneGranted = permissionsService.isMicrophoneAuthorized
        isAccessibilityTrusted = permissionsService.isAccessibilityTrusted
        isSpeechRecognitionGranted = permissionsService.isSpeechRecognitionAuthorized
    }

    private func requestMicrophone() {
        Task {
            _ = await permissionsService.requestMicrophoneAccess()
            await MainActor.run {
                refreshPermissions()
                // If still not granted after the request, permission is denied or restricted.
                // System won't show a dialog again — guide the user to System Settings.
                if !isMicrophoneGranted {
                    openSystemSettings(pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
            }
        }
    }

    private func requestAccessibility() {
        _ = permissionsService.promptAccessibilityTrusted()
        openSystemSettings(pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func requestSpeechRecognition() {
        Task {
            _ = await permissionsService.requestSpeechRecognitionAccess()
            await MainActor.run { refreshPermissions() }
        }
    }

    private func openSystemSettings(pane: String) {
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    var isOptional: Bool = false
    var isInformational: Bool = false
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isGranted ? .green : (isOptional ? Theme.accent.opacity(0.7) : Theme.textMuted))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.navy)
                    if isOptional {
                        Text("Optional")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer()

            if isInformational {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            } else if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else if let action = action {
                Button("Grant", action: action)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(height: 76)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isGranted ? Color.green.opacity(0.3) : Theme.textMuted.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isEnabled ? Theme.accent.opacity(configuration.isPressed ? 0.8 : 1.0) : Color.gray.opacity(0.3))
            .foregroundColor(isEnabled ? .white : Color(white: 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ContinueButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isEnabled ? Theme.accent.opacity(configuration.isPressed ? 0.8 : 1.0) : Color.gray.opacity(0.3))
            .foregroundColor(isEnabled ? .white : Color(white: 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
