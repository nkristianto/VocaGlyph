import Foundation
import Combine
import AVFoundation

enum AppState {
    case idle
    case initializing
    case recording
    case processing
}

protocol AppStateManagerDelegate: AnyObject {
    func appStateDidChange(newState: AppState)
    func appStateManagerDidTranscribe(text: String)
}

class AppStateManager: ObservableObject, @unchecked Sendable {
    weak var delegate: AppStateManagerDelegate?
    var engineRouter: EngineRouter?
    var sharedWhisper: WhisperService?
    var postProcessingEngine: (any PostProcessingEngine)?

    /// Singleton local LLM engine — persists model weights in Unified Memory.
    /// Recreated only when the user switches to a different model ID.
    private var _localLLMEngine: LocalLLMEngine?
    private var _localLLMEngineModelId: String?

    private var localLLMEngine: LocalLLMEngine {
        let modelId = UserDefaults.standard.string(forKey: "selectedLocalLLMModel") ?? "mlx-community/Qwen2.5-7B-Instruct-4bit"
        if let existing = _localLLMEngine, _localLLMEngineModelId == modelId {
            return existing
        }
        Logger.shared.info("AppStateManager: Creating LocalLLMEngine for model: \(modelId)")
        let engine = LocalLLMEngine(modelId: modelId)
        _localLLMEngine = engine
        _localLLMEngineModelId = modelId
        return engine
    }

    /// Download/load progress for the local LLM model.
    /// - `nil`: no active download
    /// - `0.0 ..< 1.0`: downloading / loading
    /// - `1.0`: complete (set back to nil after 1.5 s)
    @Published var localLLMDownloadProgress: Double? = nil

    /// `true` when the local LLM is fully loaded in Unified Memory and shader-warmed.
    /// Drive UI "Model Ready" / "Loading…" indicator from this.
    @Published var localLLMIsWarmedUp: Bool = false

    /// `true` when the model files exist in the HuggingFace disk cache.
    @Published var localLLMIsDownloaded: Bool = false

    // We no longer track selectedEngine explicitly. We derive the engine 
    // from the model selection inside switchTranscriptionEngine.
    
    @Published var currentState: AppState = .idle {
        didSet {
            delegate?.appStateDidChange(newState: currentState)
        }
    }
    
    init() {}
    
    func startEngine() {
        let initialModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "apple-native"
        Logger.shared.info("AppStateManager: startEngine called with model: \(initialModel)")
        Task {
            await switchTranscriptionEngine(toModel: initialModel)
        }

        switchPostProcessingEngine()

        // Strategy 1: Eagerly warm up the local LLM in the background if it is
        // already selected AND the model weights are on disk. This eliminates the
        // 5–30 s lag users would otherwise experience on their first dictation.
        // We never trigger a network download here — only load from disk.
        warmUpLocalLLMIfNeeded()
    }

    /// Fires a background Task to preload + Metal-warm the local LLM when:
    ///   1. `selectedTaskModel == "local-llm"` (user has chosen local AI)
    ///   2. Post-processing is enabled
    ///   3. Model weights already exist on disk (no download required)
    ///
    /// Runs at `.background` priority so it never contends with UI or audio.
    private func warmUpLocalLLMIfNeeded() {
        let selectedPostModel = UserDefaults.standard.string(forKey: "selectedTaskModel") ?? "apple-native"
        let postProcessingEnabled = UserDefaults.standard.bool(forKey: "enablePostProcessing")

        guard selectedPostModel == "local-llm", postProcessingEnabled else {
            Logger.shared.info("AppStateManager: Background LLM warm-up skipped (local-llm not selected or post-processing disabled)")
            return
        }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let engine = self.localLLMEngine
            let isOnDisk = await engine.isModelDownloaded()
            guard isOnDisk else {
                Logger.shared.info("AppStateManager: Background LLM warm-up skipped — model not on disk yet")
                return
            }
            Logger.shared.info("AppStateManager: Starting background LLM warm-up (model is on disk)")
            await self.preloadLocalLLMModel()
            Logger.shared.info("AppStateManager: Background LLM warm-up complete")
            await MainActor.run { self.localLLMIsWarmedUp = true }
        }
    }
    
    public func switchPostProcessingEngine() {
        let selectedPostModel = UserDefaults.standard.string(forKey: "selectedTaskModel") ?? "apple-native"
        Logger.shared.info("AppStateManager: Switching post-processing engine to: \(selectedPostModel)")
        
        if selectedPostModel == "cloud-api" {
            let selectedCloudProvider = UserDefaults.standard.string(forKey: "selectedCloudProvider") ?? "gemini"
            if selectedCloudProvider == "anthropic" {
                self.postProcessingEngine = AnthropicEngine()
            } else {
                self.postProcessingEngine = GeminiEngine()
            }
        } else if selectedPostModel == "apple-native" {
            if #available(macOS 26.0, *) {
                // Foundation Models framework is available — use the real on-device Apple Intelligence engine.
                Logger.shared.info("AppStateManager: macOS 26+ detected — using real AppleIntelligenceEngine (Foundation Models)")
                self.postProcessingEngine = AppleIntelligenceEngine()
            } else {
                // Foundation Models framework is not available on macOS 15.x.
                // Use a stub that throws a descriptive error so the orchestrator can log it clearly.
                Logger.shared.info("AppStateManager: macOS < 26 detected — Foundation Models unavailable, using legacy stub")
                self.postProcessingEngine = AppleIntelligenceLegacyStub()
            }
        } else if selectedPostModel == "local-llm" {
            let selectedLocalModel = UserDefaults.standard.string(forKey: "selectedLocalLLMModel") ?? "mlx-community/Qwen2.5-7B-Instruct-4bit"
            Logger.shared.info("AppStateManager: Switching post-processing engine to LocalLLMEngine (model: \(selectedLocalModel))")
            self.postProcessingEngine = localLLMEngine
            Task { self.localLLMIsDownloaded = await localLLMEngine.isModelDownloaded() }
        } else {
            self.postProcessingEngine = nil
        }
    }
    
    func startRecording() {
        currentState = .recording
    }
    
    func stopRecording() {
        currentState = .processing
    }
    
    func setIdle() {
        currentState = .idle
    }
    
    func setInitializing() {
        currentState = .initializing
    }
    
    func processAudio(buffer: AVAudioPCMBuffer) {
        Logger.shared.info("AppStateManager: processAudio called with buffer size: \(buffer.frameLength)")
        guard let router = engineRouter else {
            Logger.shared.info("AppStateManager: engineRouter is nil. Aborting.")
            setIdle()
            return
        }

        let shouldPostProcess = UserDefaults.standard.bool(forKey: "enablePostProcessing")
        let postProcessPrompt = UserDefaults.standard.string(forKey: "postProcessingPrompt") ?? ""

        Task {
            // ── Stage 1: Transcription (15s timeout) ─────────────────────────────
            let text: String
            do {
                text = try await withThrowingTaskGroup(of: String.self) { group in
                    group.addTask { try await router.transcribe(audioBuffer: buffer) }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15_000_000_000)
                        throw NSError(domain: "TimeoutError", code: 408,
                                      userInfo: [NSLocalizedDescriptionKey: "Transcription timed out after 15s"])
                    }
                    guard let result = try await group.next() else { throw CancellationError() }
                    group.cancelAll()
                    return result
                }
                Logger.shared.info("AppStateManager: Transcription complete: '\(text)'")
            } catch {
                Logger.shared.error("AppStateManager: Transcription failed — \(error.localizedDescription)")
                DispatchQueue.main.async { self.setIdle() }
                return
            }

            // ── Stage 2: Post-Processing (30s timeout) ────────────────────────────
            var finalText = text
            if shouldPostProcess,
               let postProcessor = self.postProcessingEngine,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Logger.shared.info("AppStateManager: [PostProcessing] Starting with prompt: '\(postProcessPrompt)'")
                do {
                    let refined = try await withThrowingTaskGroup(of: String.self) { group in
                        group.addTask { try await postProcessor.refine(text: text, prompt: postProcessPrompt) }
                        group.addTask {
                            try await Task.sleep(nanoseconds: 30_000_000_000)
                            throw NSError(domain: "TimeoutError", code: 408,
                                          userInfo: [NSLocalizedDescriptionKey: "Post-processing timed out after 30s"])
                        }
                        guard let result = try await group.next() else { throw CancellationError() }
                        group.cancelAll()
                        return result
                    }
                    Logger.shared.info("AppStateManager: [PostProcessing] Done. Result: '\(refined)'")
                    finalText = refined
                } catch let error as AppleIntelligenceError {
                    let engineName = type(of: postProcessor)
                    Logger.shared.error("AppStateManager: [PostProcessing] \(engineName) failed — \(error.localizedDescription). Using raw transcription.")
                } catch {
                    let engineName = type(of: postProcessor)
                    Logger.shared.error("AppStateManager: [PostProcessing] \(engineName) failed — \(error.localizedDescription). Using raw transcription.")
                }
            }

            DispatchQueue.main.async {
                Logger.shared.info("AppStateManager: Dispatching back to main UI thread...")
                if let del = self.delegate {
                    Logger.shared.info("AppStateManager: Delegate exists, calling appStateManagerDidTranscribe()")
                    del.appStateManagerDidTranscribe(text: finalText)
                } else {
                    Logger.shared.info("AppStateManager: ERROR! Delegate is unexpectedly nil!")
                }
                self.setIdle()
            }
        }
    }

    public func switchTranscriptionEngine(toModel modelName: String) async {
        guard let router = engineRouter else { return }
        
        Logger.shared.info("AppStateManager: Requested to switch transcription engine to model: '\(modelName)'")
        
        if modelName == "apple-native" {
            if #available(macOS 15.0, *) {
                Logger.shared.info("AppStateManager: Dynamically routing to NativeSpeechEngine for model: apple-native")
                let native = NativeSpeechEngine()
                await router.setEngine(native)
            } else {
                // Fallback if somehow triggered on old macOS
                Logger.shared.error("AppStateManager: macOS too old for apple-native. Falling back to WhisperKit.")
                if let whisper = sharedWhisper { await router.setEngine(whisper) }
            }
        } else {
            Logger.shared.info("AppStateManager: Dynamically routing to shared WhisperService for model: \(modelName)")
            if let whisper = sharedWhisper {
                await router.setEngine(whisper)
            }
        }
    }

    /// Evicts the local LLM model from Unified Memory.
    /// Called from `SettingsView` when the user presses "Free Model Memory".
    /// Never call `localLLMEngine.unloadModel()` directly from UI — always go through the Orchestrator.
    public func unloadLocalLLMEngine() async {
        await localLLMEngine.unloadModel()
    }

    /// Downloads and loads the local LLM model into Unified Memory, reporting progress
    /// via `@Published localLLMDownloadProgress`. Safe to call from a SwiftUI `Task {}`.
    public func preloadLocalLLMModel() async {
        DispatchQueue.main.async { self.localLLMDownloadProgress = 0.0 }
        do {
            try await localLLMEngine.preloadModel { [weak self] fraction in
                // DispatchQueue.main.async is safe here: mlx's Hub downloader calls this
                // closure on a background thread. Task { @MainActor } can trigger a Swift
                // concurrency runtime SIGABRT in release builds from non-async contexts.
                DispatchQueue.main.async { self?.localLLMDownloadProgress = fraction }
            }
            DispatchQueue.main.async {
                self.localLLMDownloadProgress = 1.0
                self.localLLMIsDownloaded = true
            }
            // Reset progress indicator after a short delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            DispatchQueue.main.async { self.localLLMDownloadProgress = nil }
        } catch {
            Logger.shared.error("AppStateManager: Model preload failed — \(error.localizedDescription)")
            DispatchQueue.main.async { self.localLLMDownloadProgress = nil }
        }
    }

    /// Deletes the downloaded model files from disk and evicts from RAM.
    public func deleteLocalLLMModel() async {
        do {
            try await localLLMEngine.deleteModelFromDisk()
            await MainActor.run {
                self.localLLMIsDownloaded = false
                self.localLLMDownloadProgress = nil
            }
        } catch {
            Logger.shared.error("AppStateManager: Model deletion failed — \(error.localizedDescription)")
        }
    }
}

extension AppStateManager {
    static func isMacOS15OrNewer() -> Bool {
        if #available(macOS 15.0, *) {
            return true
        } else {
            return false
        }
    }
}
