import SwiftUI

/// A row representing a single transcription model inside a shared group card.
///
/// Layout (2-row):
/// - Row 1: [selection circle]  [Model Name · size]  [speed badge]  [ACTIVE badge]
/// - Row 2: [description (grows)] | [action buttons (trailing, only when not active)]
struct ModelCardView: View {
    let title: String
    let description: String
    let size: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isActive: Bool
    let isLoading: Bool
    let downloadProgress: Float?
    /// When true, shows an indeterminate spinner instead of the static Download button.
    var isDownloadInProgress: Bool = false
    /// Optional speed/recommendation badge shown inline in the title row.
    var recommendationBadge: String? = nil
    let onSelect: () -> Void
    let onUse: () -> Void
    let onDownload: () -> Void
    let onDeleteRequest: (() -> Void)?

    /// The title with any trailing "(…)" removed, e.g. "Large v3 Turbo ⭐"
    private var baseName: String {
        title.replacingOccurrences(of: #"\s*\([^)]+\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The text inside the first "(…)" in the title, e.g. "Multilingual"
    private var bracketLabel: String? {
        guard let start = title.firstIndex(of: "("),
              let end   = title.firstIndex(of: ")"),
              end > start else { return nil }
        let inner = title[title.index(after: start)..<end]
        return inner.isEmpty ? nil : String(inner)
    }

    @GestureState private var isPressed = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 4pt left accent bar for the active model
            if isActive {
                Rectangle()
                    .frame(width: 4)
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // ── Left content: title + badges + description ────────────
            VStack(alignment: .leading, spacing: 6) {
                // Row 1: selection circle + title + ACTIVE pill
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? Theme.navy : Theme.textMuted)
                        .font(.system(size: 16))

                    Text(baseName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isActive ? Theme.accent : Theme.navy)

                    Spacer()

                    if isActive {
                        activeBadge
                    }
                }

                // Row 1.5: badge strip
                HStack(spacing: 5) {
                    // Bracket label chip e.g. "Multilingual", "English-only"
                    if let label = bracketLabel {
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.textMuted.opacity(0.08))
                            .clipShape(.rect(cornerRadius: 4))
                    }

                    // Size chip
                    if !size.isEmpty && size != "0 MB" {
                        Label(size, systemImage: "internaldrive")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.textMuted.opacity(0.08))
                            .clipShape(.rect(cornerRadius: 4))
                    }

                    // Speed / recommendation badge
                    if let badge = recommendationBadge {
                        speedBadgeView(badge)
                    }
                }
                .padding(.leading, 24)

                // Row 2: description only
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(3)
                    .padding(.leading, 24)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // ── Trailing: action buttons — vertically centered ────────
            if !isActive {
                actionButtons
                    .padding(.trailing, 14)
            }
        }
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
    }

    // MARK: - Sub-views

    /// Background colour for the full row, covering all states.
    private var rowBackground: Color {
        if isActive    { return Theme.accent.opacity(0.06) }
        if isSelected  { return Theme.navy.opacity(0.04) }
        if isPressed   { return Theme.navy.opacity(0.03) }
        return Color.clear
    }

    /// Green "ACTIVE" pill badge.
    @ViewBuilder
    private var activeBadge: some View {
        Text("ACTIVE")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.green.opacity(0.15))
            .foregroundStyle(Color.green)
            .clipShape(.rect(cornerRadius: 4))
    }

    @ViewBuilder
    private func speedBadgeView(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.accent.opacity(0.1))
            .clipShape(.rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    /// Action buttons — shown in the trailing column of Row 2.
    @ViewBuilder
    private var actionButtons: some View {
        if isDownloadInProgress {
            downloadInProgressView
        } else if !isDownloaded {
            downloadingOrDownloadButton
        } else {
            useAndDeleteButtons
        }
    }

    @ViewBuilder
    private var downloadInProgressView: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Downloading...")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(Theme.accent.opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
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
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private var useAndDeleteButtons: some View {
        HStack(spacing: 6) {
            Button(action: {
                Logger.shared.debug("Settings: Clicked Use Model for \(title)")
                onUse()
            }) {
                if isLoading {
                    HStack(spacing: 4) {
                        ProgressView().progressViewStyle(.circular).controlSize(.mini)
                        Text("Initializing...")
                    }
                    .font(.system(size: 11, weight: .semibold))
                } else {
                    Text("Use Model")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
            .tint(isLoading ? Theme.textMuted : Theme.navy)

            if let deleteRequestAction = onDeleteRequest {
                Button(action: { deleteRequestAction() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .tint(Color.red)
                .foregroundStyle(Color.red)
            }
        }
    }
}
