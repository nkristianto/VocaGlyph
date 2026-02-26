import SwiftUI

/// Local LLM sub-section: model size picker, RAM info, download/delete controls.
struct LocalLLMSection: View {
    @ObservedObject var stateManager: AppStateManager
    @AppStorage("selectedLocalLLMModel") private var selectedLocalLLMModel: String = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    var body: some View {
        Group {
            modelPicker
            ramInfo
            Divider().background(Theme.textMuted.opacity(0.1))
            downloadStatusRow
            Divider().background(Theme.textMuted.opacity(0.1))
            if stateManager.localLLMIsDownloaded {
                deleteRow
                Divider().background(Theme.textMuted.opacity(0.1))
            }
        }
    }

    // MARK: - Model Picker

    @ViewBuilder
    private var modelPicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Local Model")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Select model size (larger = better quality, more RAM)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Menu {
                Button("Qwen 2.5 1.5B (1.1 GB, 8GB RAM)") {
                    selectedLocalLLMModel = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
                    stateManager.switchPostProcessingEngine()
                }
                Button("Qwen 2.5 3B (2.0 GB, 8GB RAM)") {
                    selectedLocalLLMModel = "mlx-community/Qwen2.5-3B-Instruct-4bit"
                    stateManager.switchPostProcessingEngine()
                }
            } label: {
                HStack {
                    Text(selectedLocalLLMModel == "mlx-community/Qwen2.5-3B-Instruct-4bit" ? "Qwen 2.5 3B" : "Qwen 2.5 1.5B")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.navy)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 160)
        }
        .padding(16)
    }

    // MARK: - RAM Info

    @ViewBuilder
    private var ramInfo: some View {
        if selectedLocalLLMModel == "mlx-community/Qwen2.5-3B-Instruct-4bit" {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Requires ~2.0 GB disk + 8 GB RAM. Model downloads once and is cached.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Download / Status Row

    @ViewBuilder
    private var downloadStatusRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if stateManager.localLLMIsWarmedUp {
                        Image(systemName: "bolt.circle.fill").foregroundStyle(.green)
                        Text("Model ready in memory").fontWeight(.semibold).foregroundStyle(Theme.navy)
                    } else if stateManager.localLLMIsDownloaded && stateManager.localLLMDownloadProgress != nil {
                        ProgressView().controlSize(.mini).tint(Theme.accent)
                        Text("Loading model into memory…").fontWeight(.semibold).foregroundStyle(Theme.navy)
                    } else if stateManager.localLLMIsDownloaded {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Model downloaded").fontWeight(.semibold).foregroundStyle(Theme.navy)
                    } else {
                        Image(systemName: "arrow.down.circle").foregroundStyle(Theme.navy)
                        Text("Model not downloaded").fontWeight(.semibold).foregroundStyle(Theme.navy)
                    }
                }

                if let progress = stateManager.localLLMDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .frame(maxWidth: 240)
                        Text(progress < 1.0 ? "Downloading… \(Int(progress * 100))%" : "✅ Complete!")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                    }
                } else if !stateManager.localLLMIsDownloaded {
                    Text("Download the model before your first use to avoid delays during dictation.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                } else if !stateManager.localLLMIsWarmedUp {
                    Text("Model loaded on next use. Launch app again to warm up automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Spacer()
            if stateManager.localLLMDownloadProgress != nil {
                ProgressView().controlSize(.small)
            } else if !stateManager.localLLMIsDownloaded {
                Button("Download") {
                    Task { await stateManager.preloadLocalLLMModel() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(16)
    }

    // MARK: - Delete Row

    @ViewBuilder
    private var deleteRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Delete Model from Disk")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.navy)
                Text("Removes downloaded weights from your HuggingFace cache.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button("Delete") {
                Task { await stateManager.deleteLocalLLMModel() }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(16)
    }
}
