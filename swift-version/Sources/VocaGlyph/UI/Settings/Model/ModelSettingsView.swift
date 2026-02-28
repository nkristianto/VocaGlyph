import SwiftUI

/// Coordinator view for the Model settings tab.
/// Shows all Whisper model cards and handles the delete-confirmation overlay.
struct ModelSettingsView: View {
    @ObservedObject var whisper: WhisperService
    @ObservedObject var parakeet: ParakeetService
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
                            // ⚡ Speed-First (Parakeet) section — above Whisper models
                            Label {
                                Text("⚡ Speed-First (Parakeet)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.navy)
                            } icon: {
                                EmptyView()
                            }
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            appleNativeCard
                            // Divider before Whisper section
                            Divider()
                                .background(Theme.textMuted.opacity(0.2))
                                .padding(.vertical, 4)

                            parakeetCard(
                                id: "parakeet-v3",
                                title: "Parakeet TDT v3 (Multilingual)",
                                description: "NVIDIA Parakeet TDT CoreML. Supports 25 European languages + English. ~190× real-time on Apple Silicon ANE. Zero cloud dependency.",
                                size: "483 MB",
                                recommendationBadge: "⚡ ~20× faster than Whisper"
                            )
                            parakeetCard(
                                id: "parakeet-v2",
                                title: "Parakeet TDT v2 (English-only)",
                                description: "English-only Parakeet TDT model. Slightly smaller footprint than v3. Ideal for English-only workflows on lower-RAM Macs.",
                                size: "464 MB"
                            )

                            // Divider before Whisper section
                            Divider()
                                .background(Theme.textMuted.opacity(0.2))
                                .padding(.vertical, 4)

                            
                            whisperCard(id: "small", title: "Small (Multilingual)",
                                        description: "Higher accuracy with acceptable speeds on modern Mac hardware.",
                                        size: "240 MB")
                            whisperCard(id: "large-v3-v20240930_626MB", title: "Large v3 Quantized (Multilingual) ⭐",
                                        description: "Best under-1GB multilingual model. Near large-v3 accuracy at only ~626 MB. Great for Indonesian on any Apple Silicon Mac.",
                                        size: "626 MB")
                            whisperCard(id: "medium", title: "Medium (Multilingual)",
                                        description: "99-language multilingual model. Good Indonesian accuracy (~14% WER). Best balance of speed and quality for non-English dictation on 8 GB Macs.",
                                        size: "1.5 GB")
                            whisperCard(id: "large-v3_turbo", title: "Large v3 Turbo (Multilingual) ⭐",
                                        description: "Speed-optimised large-v3 variant. Near-identical accuracy at 2× faster inference. Best choice for Indonesian on 16 GB Macs.",
                                        size: "1.5 GB")
                            whisperCard(id: "distil-whisper_distil-large-v3",
                                        title: "Distil Large v3",
                                        description: "Distil-Whisper English-optimised model. Fast inference at ~60% of large-v3 size. English only — use multilingual models above for Indonesian.",
                                        size: "1.5 GB",
                                        recommendationBadge: "⚡ ~2× faster · English-optimised")
                            whisperCard(id: "large-v3", title: "Large v3 (Multilingual) ⭐",
                                        description: "Best overall multilingual accuracy. Top Indonesian performance (~7% WER). Requires 16 GB RAM and Apple Silicon.",
                                        size: "3 GB")
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
    private func whisperCard(
        id: String,
        title: String,
        description: String,
        size: String,
        recommendationBadge: String? = nil
    ) -> some View {
        ModelCardView(
            title: title,
            description: description,
            size: size,
            isSelected: focusedModel == id,
            isDownloaded: whisper.downloadedModels.contains(id),
            isActive: selectedModel == id && whisper.activeModel == id,
            isLoading: whisper.loadingModel == id,
            downloadProgress: whisper.downloadProgresses[id],
            recommendationBadge: recommendationBadge,
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

    /// Parakeet model card builder — mirrors whisperCard() exactly.
    @ViewBuilder
    private func parakeetCard(
        id: String,
        title: String,
        description: String,
        size: String,
        recommendationBadge: String? = nil
    ) -> some View {
        let isDownloading = parakeet.downloadingModelId == id
        let isAlreadyDownloaded = parakeet.downloadedModels.contains(id)

        ModelCardView(
            title: title,
            description: description,
            size: size,
            isSelected: focusedModel == id,
            isDownloaded: isAlreadyDownloaded,
            isActive: selectedModel == id && parakeet.activeModel == id,
            // "Initializing..." spinner on the Use Model button (post-download ANE load phase)
            isLoading: isDownloading && isAlreadyDownloaded,
            // Show phased progress % (25%, 60%, 85%) from ParakeetService.loadingProgress
            // so ModelCardView renders the animated arrow + percentage, identical to Whisper.
            downloadProgress: isDownloading && !isAlreadyDownloaded ? Float(parakeet.loadingProgress) : nil,
            recommendationBadge: recommendationBadge,
            onSelect: { focusedModel = id },
            onUse: {
                selectedModel = id
                parakeet.changeModel(to: id)
                Task { await stateManager.switchTranscriptionEngine(toModel: id) }
            },
            onDownload: {
                parakeet.downloadOnly(id: id)
            },

            onDeleteRequest: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    modelToDeleteTitle = title
                    modelDeleteAction = { parakeet.deleteModel(id: id) }
                }
            }
        )
    }
}

