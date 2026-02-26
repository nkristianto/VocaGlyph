import SwiftUI

/// Displays a red error banner when the SettingsViewModel has an error message.
struct ErrorDisplaySection: View {
    let errorMessage: String?

    var body: some View {
        if let errorMessage {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        }
    }
}
