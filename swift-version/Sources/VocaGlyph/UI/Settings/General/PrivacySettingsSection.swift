import SwiftUI

/// Privacy section: Privacy Mode toggle.
///
/// When Privacy Mode is enabled the app skips writing new transcription results
/// to the local SwiftData history store. Transcription output is still typed
/// into the target app as normal — only the history record is suppressed.
///
/// Application logs already respect the existing "Enable Debug Logging" toggle
/// (off by default). Keeping that toggle off also prevents transcribed text
/// from appearing in the log file.
struct PrivacySettingsSection: View {
    @AppStorage("privacyModeEnabled") private var isPrivacyModeEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Privacy")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.navy)
            }

            VStack(spacing: 0) {
                // Privacy Mode
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy Mode")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Stop recording transcription history while this is enabled. Disable debug logging to also prevent text from appearing in application logs.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $isPrivacyModeEnabled.logged(name: "Privacy Mode"))
                        .labelsHidden()
                        .toggleStyle(.switch)
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
