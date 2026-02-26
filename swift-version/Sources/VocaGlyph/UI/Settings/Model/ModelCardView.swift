import SwiftUI

/// A card representing a single Whisper model: shows title, description, size badge,
/// download/use/delete actions and progress tracking.
struct ModelCardView: View {
    let title: String
    let description: String
    let size: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isActive: Bool
    let isLoading: Bool
    let downloadProgress: Float?
    /// Optional speed/recommendation badge text shown below the title row (e.g. "⚡ ~2× faster · English-optimised").
    var recommendationBadge: String? = nil
    let onSelect: () -> Void
    let onUse: () -> Void
    let onDownload: () -> Void
    let onDeleteRequest: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)
                .font(.system(size: 16))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                headerRow
                if let badge = recommendationBadge {
                    speedBadgeView(badge)
                }
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
                actionRow
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(isSelected ? Theme.navy.opacity(0.05) : Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.navy : Theme.textMuted.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var headerRow: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isActive ? Color.green : Theme.navy)
            Spacer()
            if isActive {
                badge("ACTIVE", bg: Color.green, fg: .white)
            } else if isDownloaded {
                badge("DOWNLOADED", bg: Theme.accent.opacity(0.1), fg: Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(0.2), lineWidth: 1))
            }
            Text(size)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.textMuted.opacity(0.1), lineWidth: 1))
                .foregroundStyle(Theme.textMuted)
                .clipShape(.rect(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func badge(_ label: String, bg: Color, fg: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(.rect(cornerRadius: 4))
    }

    @ViewBuilder
    private func speedBadgeView(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.accent.opacity(0.1))
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var actionRow: some View {
        if !isDownloaded {
            downloadingOrDownloadButton
        } else if !isActive {
            useAndDeleteButtons
        }
    }

    @ViewBuilder
    private var downloadingOrDownloadButton: some View {
        if let progress = downloadProgress {
            HStack(spacing: 6) {
                if #available(macOS 14.0, *) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Theme.accent)
                }
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Theme.accent.opacity(0.1))
            .clipShape(.rect(cornerRadius: 6))
        } else {
            Button(action: {
                Logger.shared.debug("Settings: Clicked Download for \(title)")
                onDownload()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download")
                }
                .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Theme.accent.opacity(0.1))
            .clipShape(.rect(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var useAndDeleteButtons: some View {
        HStack(spacing: 8) {
            Button(action: {
                Logger.shared.debug("Settings: Clicked Use Model for \(title)")
                onUse()
            }) {
                HStack(spacing: 4) {
                    if isLoading {
                        ProgressView().progressViewStyle(.circular).controlSize(.small).padding(.trailing, 2)
                        Text("Initializing...")
                    } else {
                        Image(systemName: "play.circle")
                        Text("Use Model")
                    }
                }
                .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .foregroundStyle(isLoading ? Theme.textMuted : Theme.navy)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background((isLoading ? Theme.textMuted : Theme.navy).opacity(0.1))
            .clipShape(.rect(cornerRadius: 6))

            if let deleteRequestAction = onDeleteRequest {
                Button(action: { deleteRequestAction() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .foregroundStyle(.red)
                .padding(.vertical, 4).padding(.horizontal, 8)
                .background(Color.red.opacity(0.1))
                .clipShape(.rect(cornerRadius: 6))
            }
        }
    }
}
