import SwiftUI

struct OnboardingView: View {
    @State private var permissionsService: PermissionsService
    var onContinue: () -> Void
    
    // UI state for reactive updates
    @State private var isMicrophoneGranted = false
    @State private var isAccessibilityTrusted = false
    @State private var isFullDiskAccessGranted = false
    
    // Timer to poll for external permission changes (like System Settings)
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    init(permissionsService: PermissionsService, onContinue: @escaping () -> Void) {
        self._permissionsService = State(initialValue: permissionsService)
        self.onContinue = onContinue
    }
    
    var allGranted: Bool {
        return isMicrophoneGranted && isAccessibilityTrusted
    }
    
    var body: some View {
        VStack(spacing: 20) {
            if let imgUrl = Bundle.module.url(forResource: "appicon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: imgUrl) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding(.top, 20)
            } else {
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 20)
            }
            
            Text("Welcome to VocaGlyph")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Theme.navy)
            
            Text("To provide seamless global dictation, VocaGlyph needs a few permissions to operate correctly.")
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
                .padding(.horizontal, 40)
            
            VStack(spacing: 16) {
                // Microphone
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required to capture your voice for transcription.",
                    isGranted: isMicrophoneGranted,
                    action: requestMicrophone
                )
                
                // Accessibility
                PermissionRow(
                    icon: "keyboard.fill",
                    title: "Accessibility",
                    description: "Required to type transcribed text directly into your active app.",
                    isGranted: isAccessibilityTrusted,
                    action: requestAccessibility
                )
                
                // Full Disk Access (Informational Only)
                PermissionRow(
                    icon: "internaldrive.fill",
                    title: "Full Disk Access",
                    description: "Required when loading offline Apple-Native or MLX models. It will prompt automatically when needed.",
                    isGranted: true, // Force true to show informational "checkmark" or we can pass a special flag
                    isInformational: true,
                    action: nil
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Continue")
            }
            .buttonStyle(ContinueButtonStyle())
            .disabled(!allGranted)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .frame(width: 500, height: 680)
        .background(Color.white) // Match settings page
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
        isFullDiskAccessGranted = permissionsService.isFullDiskAccessGranted
    }
    
    private func requestMicrophone() {
        Task {
            _ = await permissionsService.requestMicrophoneAccess()
            await MainActor.run {
                refreshPermissions()
            }
        }
    }
    
    private func requestAccessibility() {
        _ = permissionsService.promptAccessibilityTrusted()
        openSystemSettings(pane: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    
    // Request Full Disk Access is no longer triggered from here
    
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
    var isInformational: Bool = false
    let action: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(isGranted || isInformational ? .green : Theme.textMuted)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.navy)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }
            
            Spacer()
            
            if isInformational {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
            } else if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if let action = action {
                Button("Grant", action: action)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
        .background(Color.white) // Match settings form sections
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.textMuted.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
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
