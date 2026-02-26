import SwiftUI

/// Developer Options section: debug logging toggle and log-file reveal button.
struct DeveloperOptionsSection: View {
    @AppStorage("enableDebugLogging") private var isDebugEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Developer Options")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "hammer.fill")
                    .foregroundStyle(Theme.navy)
            }

            VStack(spacing: 0) {
                // Enable Debug Logging
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Debug Logging")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Save internal operation logs to a local file for troubleshooting")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $isDebugEnabled.logged(name: "Debug Logging"))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(16)

                Divider()
                    .background(Theme.textMuted.opacity(0.1))
                    .padding(.horizontal, 16)

                // Reveal Log File
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Application Logs")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("View the unified local log file")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        Logger.shared.debug("Settings: Clicked Reveal in Finder")
                        NSWorkspace.shared.selectFile(Logger.shared.getLogFileURL().path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
