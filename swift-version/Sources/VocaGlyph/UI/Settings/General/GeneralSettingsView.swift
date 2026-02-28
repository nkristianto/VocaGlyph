import SwiftUI

/// Coordinator view for the General settings tab.
/// Delegates each logical section to its own sub-view.
struct GeneralSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    @Bindable var microphoneService: MicrophoneService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky Header
            VStack(alignment: .leading, spacing: 4) {
                Text("General Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.navy)
                Text("Set up your microphone, shortcut, and system preferences")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.8))

            Divider().background(Theme.textMuted.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    RecordingSetupSection(microphoneService: microphoneService)
                    SystemIntegrationSection()
                    DeveloperOptionsSection()
                }
                .padding(40)
                .padding(.bottom, 20)
            }
        }
    }
}
