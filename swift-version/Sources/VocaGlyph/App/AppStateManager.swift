import Foundation
import Combine
import AVFoundation
import SwiftData

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

    /// The shared WhisperService instance. Setting this automatically subscribes
    /// to its loading progress so the overlay can reflect real-time ETA without
    /// passing WhisperService everywhere.
    var sharedWhisper: WhisperService? {
        didSet { bindWhisperProgress() }
    }

    /// The shared ParakeetService instance, injected by AppDelegate.
    /// When a Parakeet model ID is selected, EngineRouter is pointed at this service.
    var sharedParakeet: ParakeetService? {
        didSet { bindParakeetProgress() }
    }

    var postProcessingEngine: (any PostProcessingEngine)?

    // MARK: - Memory Pressure

    /// Retained to keep the DispatchSource alive for the lifetime of AppStateManager.
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Combine
    private var whisperCancellables: Set<AnyCancellable> = []
    private var parakeetCancellables: Set<AnyCancellable> = []

    /// 0.0 → 1.0 forwarded from WhisperService.loadingProgress.
    @Published var whisperLoadingProgress: Double = 0.0
    /// ETA countdown forwarded from WhisperService.loadingEstimatedSeconds.
    @Published var whisperLoadingETA: Int = 0

    /// 0.0 → 1.0 forwarded from ParakeetService.loadingProgress.
    /// Drives the same RecordingOverlayView progress bar when a Parakeet model is loading.
    @Published var parakeetLoadingProgress: Double = 0.0

    /// Non-nil briefly when the user presses the hotkey while the engine is still loading.
    /// Cleared automatically after 3 seconds.
    @Published var notReadyMessage: String? = nil

    private func bindWhisperProgress() {
        whisperCancellables.removeAll()
        guard let whisper = sharedWhisper else { return }
        whisper.$loadingProgress
            .receive(on: DispatchQueue.main)
            .assign(to: \.whisperLoadingProgress, on: self)
            .store(in: &whisperCancellables)
        whisper.$loadingEstimatedSeconds
            .receive(on: DispatchQueue.main)
            .assign(to: \.whisperLoadingETA, on: self)
            .store(in: &whisperCancellables)
    }

    private func bindParakeetProgress() {
        parakeetCancellables.removeAll()
        guard let parakeet = sharedParakeet else { return }

        // Forward raw progress value so RecordingOverlayView can animate the bar.
        parakeet.$loadingProgress
            .receive(on: DispatchQueue.main)
            .assign(to: \.parakeetLoadingProgress, on: self)
            .store(in: &parakeetCancellables)

        // Only handle completion: when loadingProgress resets to 0 after finishing,
        // return currentState to .idle (if it was set to .initializing by switchTranscriptionEngine).
        // NOTE: we do NOT set .initializing here — that is exclusively done by switchTranscriptionEngine
        // so background downloads (clicking Download in Settings) never show the overlay.
        parakeet.$loadingProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                if progress == 0.0 && self.currentState == .initializing {
                    self.currentState = .idle
                }
            }
            .store(in: &parakeetCancellables)
    }

    /// Flash a "model still loading" message in the overlay for 3 seconds.
    /// Called by HotkeyService when the hotkey fires during .initializing state.
    func flashNotReadyMessage() {
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        let engineName = selected.hasPrefix("parakeet-") ? "Parakeet" : "WhisperKit"
        notReadyMessage = "\(engineName) is still loading. Try again in a moment."
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.notReadyMessage = nil
        }
    }

    /// SwiftData context injected by AppDelegate after ModelContainer is ready.
    /// Used by `buildActiveTemplatePrompt()` to fetch the active template at call-time.
    var modelContext: ModelContext?

    /// Singleton local LLM engine — persists model weights in Unified Memory.
    /// Recreated only when the user switches to a different model ID.
    private var _localLLMEngine: LocalLLMEngine?
    private var _localLLMEngineModelId: String?

    private var localLLMEngine: LocalLLMEngine {
        let modelId = UserDefaults.standard.string(forKey: "selectedLocalLLMModel") ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
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

        // AC #1: sequence the loads — Whisper first, then LLM.
        // switchTranscriptionEngine() returns quickly (it only calls router.setEngine).
        // The actual WhisperKit model load happens asynchronously and signals completion
        // by transitioning currentState from .initializing → .idle via the delegate.
        // We poll currentState here (500ms interval, 60s max) so warmUpLocalLLMIfNeeded()
        // never fires while Whisper is still occupying memory bandwidth.
        Task {
            await switchTranscriptionEngine(toModel: initialModel)

            // Wait for Whisper to finish loading. State goes: .idle → .initializing → .idle.
            // The first transition to .initializing happens inside WhisperService start;
            // we need the return to .idle (= "Ready" delegate callback from WhisperKit).
            let maxIterations = 120  // 120 × 0.5s = 60s max wait
            var iterations = 0
            // Give the state machine a moment to enter .initializing before we start polling.
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s ramp-up
            while currentState == .initializing && iterations < maxIterations {
                try? await Task.sleep(nanoseconds: 500_000_000)  // poll every 0.5s
                iterations += 1
            }

            let elapsedSeconds = Double(iterations + 1) * 0.5
            if currentState == .idle {
                Logger.shared.info("AppStateManager: Whisper ready after ~\(String(format: "%.1f", elapsedSeconds))s — starting LLM warm-up now.")
                warmUpLocalLLMIfNeeded()
            } else {
                Logger.shared.info("AppStateManager: Whisper not idle after \(Int(elapsedSeconds))s (state: \(currentState)) — skipping LLM warm-up.")
            }
        }

        switchPostProcessingEngine()

        // Strategy: Respond to macOS memory pressure events so the LLM model is
        // automatically evicted if the system is critically low on unified memory.
        registerMemoryPressureHandler()
    }

    /// Registers a system memory-pressure DispatchSource.
    /// On `.warning`  — logs only (model stays loaded for faster next dictation).
    /// On `.critical` — logs only; eviction is intentionally deferred until we have
    ///                   sufficient field data to determine safe thresholds.
    private func registerMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.mask
            if event.contains(.critical) {
                // Log-only: do NOT evict the LLM.
                // The user explicitly chose local post-processing; silently unloading
                // mid-session is more disruptive than the pressure itself.
                // We will revisit eviction once we have enough field data.
                Task {
                    let isLoaded = await self._localLLMEngine?.isModelLoaded() ?? false
                    Logger.shared.error("AppStateManager: 🔴 Critical memory pressure — LLM loaded=\(isLoaded). No action taken (eviction deferred).")
                }

            } else if event.contains(.warning) {
                Logger.shared.info("AppStateManager: 🟡 Memory pressure warning received — model kept loaded.")
            }
        }
        source.resume()
        memoryPressureSource = source
        Logger.shared.info("AppStateManager: Memory pressure handler registered.")
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
        let postProcessingEnabled = UserDefaults.standard.bool(forKey: "enablePostProcessing")
        guard postProcessingEnabled else {
            Logger.shared.info("AppStateManager: Post-processing is disabled — skipping engine allocation.")
            self.postProcessingEngine = nil
            return
        }

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
            let selectedLocalModel = UserDefaults.standard.string(forKey: "selectedLocalLLMModel") ?? "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
            Logger.shared.info("AppStateManager: Switching post-processing engine to LocalLLMEngine (model: \(selectedLocalModel))")
            self.postProcessingEngine = localLLMEngine
            // isModelDownloaded() is actor-isolated — await it and then update the
            // @Published property on the main thread to avoid 'Publishing from background
            // threads is not allowed' runtime warnings.
            Task {
                let downloaded = await localLLMEngine.isModelDownloaded()
                await MainActor.run { self.localLLMIsDownloaded = downloaded }
            }
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
        let (postProcessPrompt, templateName) = buildActiveTemplatePrompt()

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

            // ── Stage 1.5: Silence / Hallucination Gate ───────────────────────────
            // When the user says nothing (or only noise), the transcription engine can
            // return an empty string or one of Whisper's well-known phantom phrases.
            // Drop these here — before post-processing and before pasting — so the
            // user sees no output at all, which is the correct behaviour for silence.
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty, !AppStateManager.isSilenceHallucination(trimmedText) else {
                Logger.shared.info("AppStateManager: Dropping empty/hallucinated transcription: '\(text)'")
                DispatchQueue.main.async { self.setIdle() }
                return
            }


            // ── Stage 1.7: Word Replacement ───────────────────────────────────────
            // Applies user-defined exact word/phrase substitutions before AI post-
            // processing. Runs even when post-processing is disabled (AC #8).
            let enabledReplacements = fetchEnabledWordReplacements()
            var finalText = WordReplacementApplicator.apply(
                to: trimmedText,
                replacements: enabledReplacements
            )
            Logger.shared.info("AppStateManager: [WordReplacement] Applied \(enabledReplacements.count) pair(s). Result: '\(finalText)'")

            // ── Stage 2: Post-Processing (30s timeout) ────────────────────────────
            if shouldPostProcess,
               let postProcessor = self.postProcessingEngine,
               self.localLLMIsWarmedUp,   // AC #2: skip silently if LLM still warming up
               !finalText.isEmpty {
                Logger.shared.info("AppStateManager: [PostProcessing] Starting — template: '\(templateName)'")
                Logger.shared.debug("AppStateManager: [PostProcessing] Full prompt: '\(postProcessPrompt)'")
                do {
                    let refined = try await withThrowingTaskGroup(of: String.self) { group in
                        group.addTask { try await postProcessor.refine(text: finalText, prompt: postProcessPrompt) }
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
            } else if shouldPostProcess && !self.localLLMIsWarmedUp {
                // AC #2: LLM still loading in background — paste raw text immediately, no blocking.
                Logger.shared.info("AppStateManager: [PostProcessing] Skipped — LLM still warming up. Pasting raw transcription.")
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
        } else if modelName.hasPrefix("parakeet-") {
            // AC#5, AC#8: Route parakeet-v2 and parakeet-v3 to ParakeetService.
            // WhisperService remains loaded; EngineRouter switches exclusively to Parakeet.
            Logger.shared.info("AppStateManager: Dynamically routing to ParakeetService for model: \(modelName)")
            if let parakeet = sharedParakeet {
                // Only show the loading overlay if the model isn't already in memory.
                // Must set currentState on MainActor: didSet → appStateDidChange → NSStatusBarButton.setImage
                // all require the main thread, but switchTranscriptionEngine runs on a background thread.
                if !parakeet.isReady {
                    await MainActor.run { self.currentState = .initializing }
                }
                // AC#5: Do NOT call parakeet.changeModel() here — the UI card's onUse handler
                // already called it. This function only routes the engine, not loads a model.
                await router.setEngine(parakeet)
            } else {
                Logger.shared.error("AppStateManager: sharedParakeet is nil — cannot route to Parakeet.")
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
        // Guard: if the engine was never instantiated, there is nothing to unload.
        // Avoids force-creating a LocalLLMEngine just to call unloadModel() on a cold instance.
        guard let engine = _localLLMEngine else {
            Logger.shared.info("AppStateManager: unloadLocalLLMEngine — engine not instantiated, skipping.")
            return
        }
        await engine.unloadModel()
        // Reset warm-up flag so the UI reflects the eviction:
        // "Model ready in memory" → "Model downloaded"
        await MainActor.run {
            self.localLLMIsWarmedUp = false
        }
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

    /// Called when the user flips the "Automated Text Refinement" toggle.
    ///
    /// - When **disabled**: unloads the LLM from unified memory immediately.
    /// - When **enabled**: re-activates the engine and warms up the model in
    ///   the background if it's already on disk (no network download triggered).
    public func onPostProcessingToggled(isEnabled: Bool) {
        Logger.shared.info("AppStateManager: Post-processing toggled — enabled=\(isEnabled)")
        if isEnabled {
            switchPostProcessingEngine()
            warmUpLocalLLMIfNeeded()
        } else {
            // Unload from RAM so the memory is freed immediately.
            Task { await unloadLocalLLMEngine() }
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

// MARK: - Template Prompt Builder

extension AppStateManager {
    /// Fetches the active `PostProcessingTemplate` from SwiftData and renders it
    /// into a structured system prompt via `TemplatePromptRenderer`.
    ///
    /// Returns `(prompt, templateName)`. Both are empty strings when:
    /// - No `modelContext` is available (no SwiftData container)
    /// - No active template ID is stored in `UserDefaults`
    /// - The active template has no enabled rules
    ///
    /// AC #5: full prompt is now logged at DEBUG level only; callers log template name at INFO.
    private func buildActiveTemplatePrompt() -> (prompt: String, templateName: String) {
        guard let context = modelContext,
              let idString = UserDefaults.standard.string(forKey: TemplateSeederService.activeTemplateKey),
              let templateId = UUID(uuidString: idString) else {
            Logger.shared.info("AppStateManager: No active template ID found — skipping post-processing prompt.")
            return ("", "")
        }

        let descriptor = FetchDescriptor<PostProcessingTemplate>(
            predicate: #Predicate { $0.id == templateId }
        )
        guard let template = try? context.fetch(descriptor).first else {
            Logger.shared.error("AppStateManager: Active template ID \(templateId) not found in SwiftData.")
            return ("", "")
        }

        let prompt = TemplatePromptRenderer.render(template: template)
        Logger.shared.info("AppStateManager: Rendered template '\(template.name)' (\(prompt.count) chars)")
        return (prompt, template.name)
    }

    /// Fetches all enabled `WordReplacement` pairs from SwiftData.
    ///
    /// Returns an empty array when no `modelContext` is available or when no
    /// enabled pairs exist.  Called at the start of Stage 1.7 in `processAudio()`.
    func fetchEnabledWordReplacements() -> [(word: String, replacement: String)] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<WordReplacement>(
            predicate: #Predicate { $0.isEnabled == true },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.map { (word: $0.word, replacement: $0.replacement) }
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

    /// Returns `true` if the transcription text is a known Whisper silence hallucination.
    ///
    /// Whisper commonly emits these phrases when the audio contains silence, background
    /// noise, or is too short to decode meaningfully. None of them represent real speech.
    static func isSilenceHallucination(_ text: String) -> Bool {
        // Exact-match phrases (case-insensitive, trimmed)
        let knownPhrases: Set<String> = [
            // Whisper english silence tokens
            "thank you", "thank you.", "thanks", "thanks.",
            "thanks for watching", "thanks for watching.",
            "thank you for watching", "thank you for watching.",
            "thank you for listening", "thank you for listening.",
            "bye", "bye.", "bye-bye", "bye-bye.", "goodbye", "goodbye.",
            // "you" — Whisper's most common minimal silence output
            "you", "you.",
            // Apostrophe-prefixed variants: Whisper sometimes outputs "'you." with a leading apostrophe
            "'you.", "'you", "' you.", "' you",
            // Punctuation-only
            ".", "...", "..",
            // Common noise transcriptions
            "hmm", "hmm.", "um", "um.", "uh", "uh.",
            "mm-hmm", "mm-hmm.", "mhm", "mhm.",
            // Other common Whisper silence hallucinations
            "i see.", "i see", "okay.", "okay", "ok.", "ok",
            "yes.", "yes", "no.", "no",
            "all right.", "all right", "alright.", "alright",
            "right.", "right",
            "sure.", "sure",
            // Indonesian equivalents (common when language detection drifts)
            "terima kasih", "terima kasih.",
            "ya", "ya.", "iya", "iya.",
            "oke", "oke.", "oke.",
        ]

        let lower = text.lowercased()

        // 1. Exact phrase match
        if knownPhrases.contains(lower) { return true }

        // 2. Bracket/paren-wrapped tags e.g. [BLANK_AUDIO], (Music), [silence]
        //    These are Whisper's special token outputs for non-speech audio.
        let stripped = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        if (stripped.hasPrefix("[") && stripped.hasSuffix("]")) ||
           (stripped.hasPrefix("(") && stripped.hasSuffix(")")) {
            return true
        }

        // 3. Very short output (1-2 non-whitespace chars) — almost certainly noise
        let nonWhitespace = stripped.filter { !$0.isWhitespace }
        if nonWhitespace.count <= 2 { return true }

        return false
    }
}
