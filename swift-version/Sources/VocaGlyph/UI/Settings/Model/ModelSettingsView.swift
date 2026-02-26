import SwiftUI

/// Coordinator view for the Model settings tab.
/// Shows all Whisper model cards and handles the delete-confirmation overlay.
struct ModelSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var stateManager: AppStateManager
    @AppStorage("selectedModel") private var selectedModel: String = "apple-native"
    @State private var focusedModel: String = "apple-native"

    @State private var modelToDeleteTitle: String? = nil
    @State private var modelDeleteAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Sticky Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.navy)
                    Text("Manage offline transcription models")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.8))

                Divider().background(Theme.textMuted.opacity(0.1))

                // AI Model Section
                VStack(alignment: .leading, spacing: 16) {
                    Label {
                        Text("AI Model Local Inference")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.navy)
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(Theme.navy)
                    }

                    ScrollView {
                        VStack(spacing: 12) {
                            appleNativeCard
                            whisperCard(id: "tiny", title: "Tiny",
                                        description: "Fastest inference for Whisper. Suitable for quick commands, basic punctuation, and short sentences.",
                                        size: "75 MB")
                            whisperCard(id: "base.en", title: "Base (English Only)",
                                        description: "Optimized for English. Slightly better accuracy and speed than standard Base.",
                                        size: "140 MB")
                            whisperCard(id: "small", title: "Small (Multilingual)",
                                        description: "Higher accuracy with acceptable speeds on modern Mac hardware.",
                                        size: "240 MB")
                            whisperCard(id: "distil-whisper_distil-large-v3", title: "Distil Large v3",
                                        description: "Distil-Whisper English-optimised model. Fast inference at ~60% of large-v3 size. English only — use multilingual models below for Indonesian.",
                                        size: "1.5 GB")
                            whisperCard(id: "medium", title: "Medium (Multilingual)",
                                        description: "99-language multilingual model. Good Indonesian accuracy (~14% WER). Best balance of speed and quality for non-English dictation on 8 GB Macs.",
                                        size: "1.5 GB")
                            whisperCard(id: "large-v3-v20240930_626MB", title: "Large v3 Quantized (Multilingual) ⭐",
                                        description: "Best under-1GB multilingual model. Near large-v3 accuracy at only ~626 MB. Great for Indonesian on any Apple Silicon Mac.",
                                        size: "626 MB")
                            whisperCard(id: "large-v3", title: "Large v3 (Multilingual) ⭐",
                                        description: "Best overall multilingual accuracy. Top Indonesian performance (~7% WER). Requires 16 GB RAM and Apple Silicon.",
                                        size: "3 GB")
                            whisperCard(id: "large-v3_turbo", title: "Large v3 Turbo (Multilingual) ⭐",
                                        description: "Speed-optimised large-v3 variant. Near-identical accuracy at 2× faster inference. Best choice for Indonesian on 16 GB Macs.",
                                        size: "1.5 GB")
                        }
                        .padding(.trailing, 8)
                        .onAppear { focusedModel = selectedModel }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            // Delete Confirmation Overlay
            if let title = modelToDeleteTitle, let action = modelDeleteAction {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            modelToDeleteTitle = nil
                            modelDeleteAction = nil
                        }
                    }

                CustomConfirmationDialog(
                    title: "Delete \(title)?",
                    message: "Are you sure you want to delete this AI model? You will need to download it again before you can use it for transcription.",
                    confirmTitle: "Yes, delete it",
                    cancelTitle: "Cancel",
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            action()
                            modelToDeleteTitle = nil
                            modelDeleteAction = nil
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            modelToDeleteTitle = nil
                            modelDeleteAction = nil
                        }
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: modelToDeleteTitle != nil)
    }

    // MARK: - Card Builders

    @ViewBuilder
    private var appleNativeCard: some View {
        if #available(macOS 15.0, *) {
            ModelCardView(
                title: "Apple Intelligence Native (System)",
                description: "Apple's built-in neural dictation. Requires macOS 15.0+ and runs completely on-device. No download required.",
                size: "0 MB",
                isSelected: focusedModel == "apple-native",
                isDownloaded: true,
                isActive: selectedModel == "apple-native",
                isLoading: false,
                downloadProgress: nil,
                onSelect: { focusedModel = "apple-native" },
                onUse: {
                    selectedModel = "apple-native"
                    Task { await stateManager.switchTranscriptionEngine(toModel: "apple-native") }
                },
                onDownload: {},
                onDeleteRequest: nil
            )
        }
    }

    @ViewBuilder
    private func whisperCard(id: String, title: String, description: String, size: String) -> some View {
        ModelCardView(
            title: title,
            description: description,
            size: size,
            isSelected: focusedModel == id,
            isDownloaded: whisper.downloadedModels.contains(id),
            isActive: selectedModel == id && whisper.activeModel == id,
            isLoading: whisper.loadingModel == id,
            downloadProgress: whisper.downloadProgresses[id],
            onSelect: { focusedModel = id },
            onUse: {
                selectedModel = id
                whisper.changeModel(to: id)
                Task { await stateManager.switchTranscriptionEngine(toModel: id) }
            },
            onDownload: { whisper.downloadModel(id) },
            onDeleteRequest: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    modelToDeleteTitle = title
                    modelDeleteAction = { whisper.deleteModel(id) }
                }
            }
        )
    }
}
