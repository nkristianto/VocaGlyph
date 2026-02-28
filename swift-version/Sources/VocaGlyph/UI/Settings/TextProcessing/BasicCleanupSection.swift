import SwiftUI

/// Basic Cleanup section: Auto-Punctuation and Remove Filler Words toggles.
/// These are lightweight rules that always run, regardless of AI settings.
struct BasicCleanupSection: View {
    @AppStorage("autoPunctuation") private var autoPunctuation: Bool = true
    @AppStorage("removeFillerWords") private var removeFillerWords: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Basic Cleanup")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.navy)
            } icon: {
                Image(systemName: "scissors")
                    .foregroundStyle(Theme.navy)
            }

            Text("Lightweight rules that always run, regardless of AI settings.")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(Theme.textMuted)

            VStack(spacing: 0) {
                // Auto-Punctuation
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Punctuation")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Automatically add commas, periods, and question marks")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $autoPunctuation.logged(name: "Auto-Punctuation"))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(16)

                Divider()
                    .background(Theme.textMuted.opacity(0.1))
                    .padding(.horizontal, 16)

                // Remove Filler Words
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove Filler Words")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.navy)
                        Text("Automatically strip conversational words (um, uh, like)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $removeFillerWords.logged(name: "Remove Filler Words"))
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
