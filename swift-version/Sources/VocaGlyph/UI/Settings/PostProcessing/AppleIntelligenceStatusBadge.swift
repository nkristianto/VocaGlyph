import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Shows a live badge indicating Apple Intelligence availability for the selected model.
///
/// Three states:
/// - macOS < 26: warns that Foundation Models is unavailable
/// - macOS 26+, AI not enabled: prompts user to enable it in System Settings
/// - macOS 26+, AI available: confirms the engine is ready
struct AppleIntelligenceStatusBadge: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            #if canImport(FoundationModels)
            AppleIntelligenceStatusBadgeMacOS26()
            #else
            unsupportedBadge(message: "Rebuild with Xcode 26 SDK to enable Foundation Models.")
            #endif
        } else {
            unsupportedBadge(message: "Requires macOS 26 (Tahoe) – will fall back to raw text.")
        }
    }

    @ViewBuilder
    private func unsupportedBadge(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private struct AppleIntelligenceStatusBadgeMacOS26: View {
    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Apple Intelligence ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        case .unavailable(.appleIntelligenceNotEnabled):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence is not enabled.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                    Text("Will fall back to raw text until enabled.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.general") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

        default:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Apple Intelligence unavailable on this device – will fall back to raw text.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
#endif
