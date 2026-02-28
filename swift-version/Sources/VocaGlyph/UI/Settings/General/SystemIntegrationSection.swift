import SwiftUI

/// System Integration section: Launch at Login toggle.
struct SystemIntegrationSection: View {
    @State private var loginManager = LaunchAtLoginManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("App Behaviour")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "macwindow")
                    .foregroundStyle(Theme.navy)
            }

            VStack(spacing: 0) {
                // Launch at Login
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Automatically start VocaGlyph when you log into macOS")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { loginManager.isEnabled },
                        set: { loginManager.setEnabled($0) }
                    ))
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
