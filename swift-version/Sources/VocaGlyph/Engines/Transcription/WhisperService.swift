import Foundation
import WhisperKit
import AVFoundation

protocol WhisperServiceDelegate: AnyObject {
    func whisperServiceDidUpdateState(_ state: String)
}

class WhisperService: ObservableObject, @unchecked Sendable {
    private var whisperKit: WhisperKit?
    @Published private(set) var isReady = false
    weak var delegate: WhisperServiceDelegate?
    
    @Published var downloadProgresses: [String: Float] = [:]
    @Published var downloadState: String = "Initializing Engine..."
    @Published var downloadedModels: Set<String> = []
    
    @Published var activeModel: String = ""
    @Published var loadingModel: String? = nil

    /// Simulated 0.0→1.0 loading progress (time-extrapolated, since CoreML specialisation
    /// has no progress callback). Snaps to 1.0 when the model is actually ready.
    @Published var loadingProgress: Double = 0.0
    /// Countdown in seconds until estimated model load completion.
    @Published var loadingEstimatedSeconds: Int = 0

    private var loadingTimer: Timer?
    /// Calibrated estimate for large-v3-turbo on Apple Silicon. Shown as ETA upper-bound.
    private let estimatedLoadSeconds: Double = 35.0
    
    // Fetch from UserDefaults or fallback to recommended model
    private var defaultModelName: String {
        UserDefaults.standard.string(forKey: "selectedModel") ?? ""
    }
    
    // Convert UI string to WhisperKit locale code.
    // "Auto-Detect" (the default) returns nil — Whisper selects the language from audio.
    // "English (US)" returns "en" explicitly for users who want to lock to English.
    private var dictationLanguageCode: String? {
        let saved = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "Auto-Detect"
        switch saved {
        case "English (US)": return "en"
        case "Spanish (ES)": return "es"
        case "French (FR)": return "fr"
        case "German (DE)": return "de"
        case "Indonesian (ID)": return "id"
        default: return nil  // "Auto-Detect" or any unknown value → Whisper auto-detects
        }
    }
    
    // The default HuggingFace repo for WhisperKit CoreML models
    static let defaultModelRepo = "argmaxinc/whisperkit-coreml"

    // Base directory passed to WhisperKit.download(). No Full Disk Access or Documents
    // permission required — ~/Library/Application Support is sandbox-friendly.
    //
    // HubApi appends `models/<repo-id>` automatically, resulting in:
    //   VocaGlyph/models/argmaxinc/whisperkit-coreml/<model-variant>/
    private var baseDirectoryPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = appSupport.appendingPathComponent("VocaGlyph", isDirectory: true)
        if !FileManager.default.fileExists(atPath: baseDir.path) {
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        return baseDir
    }

    // The HubApi repoDestination for the default repo — this is where WhisperKit stores
    // downloaded model files directly (not in .cache, which is only metadata).
    //   VocaGlyph/models/argmaxinc/whisperkit-coreml/<model-variant>/
    private var repoDestination: URL {
        baseDirectoryPath
            .appendingPathComponent("models/\(WhisperService.defaultModelRepo)",
                                    isDirectory: true)
    }
    
    init() {
        migrateOldModelsDirectoryIfNeeded()
        checkDownloadedModels()
        Task {
            await autoInitialize()
        }
    }

    /// Removes the legacy doubled `VocaGlyph/models/models/...` directory that was created
    /// by a previous bug where baseDirectoryPath already contained `models` and HubApi
    /// appended another `models/<repo>` on top. Safe to delete — models will re-download
    /// into the corrected `VocaGlyph/models/argmaxinc/whisperkit-coreml/` layout.
    private func migrateOldModelsDirectoryIfNeeded() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDoubledDir = appSupport.appendingPathComponent("VocaGlyph/models/models", isDirectory: true)
        guard FileManager.default.fileExists(atPath: oldDoubledDir.path) else { return }
        do {
            try FileManager.default.removeItem(at: oldDoubledDir)
            Logger.shared.info("WhisperService: Removed legacy doubled models directory at \(oldDoubledDir.path)")
        } catch {
            Logger.shared.error("WhisperService: Could not remove legacy directory: \(error)")
        }
    }
    
    func checkDownloadedModels() {
        let downloaded = getDownloadedModelsSync()
        DispatchQueue.main.async {
            self.downloadedModels = downloaded
        }
    }
    
    private func getDownloadedModelsSync() -> Set<String> {
        let fileManager = FileManager.default
        // HubApi places model files directly under repoDestination (not in .cache/).
        let scanDir = repoDestination

        var downloaded = Set<String>()
        guard let items = try? fileManager.contentsOfDirectory(atPath: scanDir.path) else {
            return downloaded
        }
        for item in items {
            // Skip hidden directories like .cache
            guard !item.hasPrefix(".") else { continue }
            // Only count folders that contain actual model files (e.g. AudioEncoder.mlmodelc)
            let modelFolder = scanDir.appendingPathComponent(item)
            let hasModel = fileManager.fileExists(
                atPath: modelFolder.appendingPathComponent("AudioEncoder.mlmodelc").path
            )
            guard hasModel else { continue }

            // Strip known prefixes to get back to the UI variant name
            if item.hasPrefix("openai_whisper-") {
                downloaded.insert(String(item.dropFirst("openai_whisper-".count)))
            } else if item.hasPrefix("distil-whisper_") {
                downloaded.insert(item)
            }
        }
        return downloaded
    }
    
    private func autoInitialize() async {
        if defaultModelName == "apple-native" {
            DispatchQueue.main.async {
                self.downloadState = "Using Apple Native"
                self.isReady = false
            }
            return
        }
        // Do not auto-load a Whisper model when the user has selected a Parakeet
        // engine. EngineRouter will route to ParakeetService instead; loading Whisper
        // here wastes ~2s of startup time and occupies ~500 MB of unified memory.
        if defaultModelName.hasPrefix("parakeet-") {
            DispatchQueue.main.async {
                self.downloadState = "Standby"
                self.isReady = false
            }
            return
        }
        
        let available = getDownloadedModelsSync()
        if available.contains(defaultModelName) {
            // Fire the delegate BEFORE loading so AppDelegate can transition to
            // .initializing and show the loading overlay. Without this, autoInitialize
            // silently loads the model and only fires "Ready" at the end — the overlay
            // never appears on launch because setInitializing() is never triggered.
            delegate?.whisperServiceDidUpdateState("Processing")
            await initializeWhisper(modelName: defaultModelName)
        } else if let firstAvailable = available.first {
            // Fallback to whichever model is available so the user isn't outright broken
            DispatchQueue.main.async {
                self.downloadState = "Falling back to \(firstAvailable)..."
            }
            delegate?.whisperServiceDidUpdateState("Processing")
            await initializeWhisper(modelName: firstAvailable)
        } else {
            DispatchQueue.main.async {
                self.downloadState = "Model not downloaded."
                self.isReady = false
            }
        }
    }
    
    private func initializeWhisper(modelName: String) async {
        Logger.shared.info("WhisperService: Initializing WhisperKit...")
        do {
            let available = getDownloadedModelsSync()
            if !available.contains(modelName) {
                // Do not auto-download. Just return or set state.
                DispatchQueue.main.async {
                    self.downloadState = "Model not downloaded."
                    self.isReady = false
                    self.loadingModel = nil
                }
                Logger.shared.info("WhisperService: Cannot initialize model '\(modelName)', not downloaded.")
                return
            }
            
            DispatchQueue.main.async {
                self.downloadState = "Loading into memory..."
                self.loadingModel = modelName
            }

            startLoadingProgressTimer()
            
            // HubApi stores complete model files at repoDestination/<folderName>.
            // (The .cache subdirectory only contains download metadata, not the actual models.)
            let folderName = modelName.hasPrefix("distil-whisper_")
                ? modelName
                : "openai_whisper-\(modelName)"
            let modelPath = repoDestination.appendingPathComponent(folderName)
            
            Logger.shared.info("WhisperService: Model available at \(modelPath). Loading into memory...")

            // Explicitly route large model components to the Apple Neural Engine (ANE).
            // Using WhisperKit(modelFolder:) leaves compute unit selection to CoreML which may
            // fall back to CPU for heavy layers. cpuAndNeuralEngine gives 3-5× encoder speedup
            // on Apple Silicon vs the default auto-selection.
            // prewarm: true triggers CoreML on-device specialisation immediately so there
            // is no "slow first transcription" penalty when the user first presses the hotkey.
            let config = WhisperKitConfig(
                modelFolder: modelPath.path,
                // Setting tokenizerFolder to modelPath prevents WhisperKit from creating
                // HubApi(downloadBase: nil), which would default to ~/Documents/huggingface
                // and trigger the macOS sandbox Documents folder permission dialog.
                tokenizerFolder: modelPath,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndNeuralEngine,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine,
                    prefillCompute: .cpuOnly     // prefill is tiny — CPU is fine
                ),
                verbose: false,                  // suppress WhisperKit internal logs
                logLevel: .none,
                prewarm: true                    // triggers CoreML on-device specialisation early
            )
            let loadedKit = try await WhisperKit(config)

            stopLoadingProgressTimer()
            Logger.shared.info("WhisperService: WhisperKit is ready using model: \(modelName)")

            // All @Published mutations must happen on the main thread to avoid the
            // "Publishing from background threads" runtime warning and the race where
            // isReady=true becomes visible before whisperKit is written.
            DispatchQueue.main.async {
                self.whisperKit = loadedKit
                self.isReady = true
                self.activeModel = modelName
                // Only persist selectedModel if the user hasn't switched to a different engine
                // (e.g. Parakeet) since this async load started. WhisperService loads in the
                // background on every launch, and without this guard it would overwrite a
                // Parakeet or apple-native selection made during or after startup.
                let current = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
                let isStillWhisperModel = !current.hasPrefix("parakeet-") && current != "apple-native"
                if isStillWhisperModel {
                    UserDefaults.standard.set(modelName, forKey: "selectedModel")
                }
                self.loadingModel = nil
                self.downloadState = "Ready"
            }

            
            delegate?.whisperServiceDidUpdateState("Ready")
        } catch {
            stopLoadingProgressTimer()
            Logger.shared.error("WhisperService: Failed to initialize WhisperKit: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.loadingModel = nil
            }
            delegate?.whisperServiceDidUpdateState("Failed")
        }
    }
    
    // MARK: - Dynamic Configuration

    // MARK: - Loading Progress Timer

    private func startLoadingProgressTimer() {
        // IMPORTANT: Timer.scheduledTimer must be called on the main thread to be
        // scheduled on the main run loop. When `initializeWhisper` runs inside an
        // async Task, the current thread is from Swift's cooperative thread pool —
        // its run loop never runs, so timers created there never fire.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.loadingProgress = 0.0
            self.loadingEstimatedSeconds = Int(self.estimatedLoadSeconds)
            let start = Date()
            self.loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                // Asymptotic formula: progress = 1 - e^(-elapsed/τ)
                // Unlike a linear cap (e.g. min(t/35, 0.95)), this ALWAYS keeps moving
                // forward no matter how long the load takes — it just decelerates.
                // With τ=35s: ~13% at 5s, ~35% at 15s, ~63% at 35s, ~87% at 70s.
                // Snaps to 1.0 only when stopLoadingProgressTimer() is called.
                self.loadingProgress = 1.0 - exp(-elapsed / self.estimatedLoadSeconds)
                // Only show ETA countdown while still within the expected window.
                // Past that, hide it (show nothing) rather than displaying a negative number.
                let remaining = Int(self.estimatedLoadSeconds - elapsed)
                self.loadingEstimatedSeconds = remaining > 0 ? remaining : 0
            }
        }
    }


    private func stopLoadingProgressTimer() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        DispatchQueue.main.async {
            self.loadingProgress = 1.0
            self.loadingEstimatedSeconds = 0
        }
    }
    func changeModel(to modelName: String) {
        Logger.shared.info("WhisperService: Requested model change to '\(modelName)'")
        // Only load the engine if the model is actually downloaded.
        isReady = false
        let available = getDownloadedModelsSync()
        if available.contains(modelName) {
            delegate?.whisperServiceDidUpdateState("Processing") // Set to processing while loading
            Task {
                await initializeWhisper(modelName: modelName)
            }
        } else {
            Logger.shared.info("WhisperService: Model '\(modelName)' not downloaded, ignoring change request.")
            DispatchQueue.main.async {
                self.downloadState = "Model not downloaded."
            }
        }
    }
    
    /// Download a model from a HuggingFace repo that hosts WhisperKit CoreML files.
    /// - Parameters:
    ///   - modelName: The WhisperKit variant string (e.g. "large-v3_turbo", "distil-whisper_distil-large-v3")
    ///   - repo: HuggingFace repo ID. Defaults to argmaxinc/whisperkit-coreml.
    func downloadModel(_ modelName: String, from repo: String = WhisperService.defaultModelRepo) {
        Logger.shared.info("WhisperService: Starting download for model '\(modelName)' from '\(repo)'")
        DispatchQueue.main.async {
            self.downloadState = "Downloading"
            self.downloadProgresses[modelName] = 0.0
        }
        
        Task {
            do {
                _ = try await WhisperKit.download(
                    variant: modelName,
                    downloadBase: baseDirectoryPath,
                    from: repo,
                    progressCallback: { progress in
                        DispatchQueue.main.async {
                            self.downloadProgresses[modelName] = Float(progress.fractionCompleted)
                            self.downloadState = "Downloading... \(Int(progress.fractionCompleted * 100))%"
                        }
                    }
                )
                
                Logger.shared.info("WhisperService: Successfully downloaded model '\(modelName)'")
                checkDownloadedModels()
                
                DispatchQueue.main.async {
                    self.downloadProgresses.removeValue(forKey: modelName)
                    self.downloadState = "Ready"
                }
                
                // If this is the currently selected model, initialize it now
                if defaultModelName == modelName {
                    Logger.shared.info("WhisperService: Downloaded model '\(modelName)' is the default target. Initializing...")
                    await initializeWhisper(modelName: modelName)
                }
                
            } catch {
                Logger.shared.error("WhisperService: Download failed for model '\(modelName)': \(error)")
                DispatchQueue.main.async {
                    self.downloadState = "Failed"
                    self.downloadProgresses.removeValue(forKey: modelName)
                }
            }
        }
    }
    
    func deleteModel(_ modelName: String) {
        Logger.shared.info("WhisperService: Requested to delete model '\(modelName)'")
        let fileManager = FileManager.default
        let folderName = modelName.hasPrefix("distil-whisper_")
            ? modelName
            : "openai_whisper-\(modelName)"

        // Primary: model files are at repoDestination/<folderName>
        let primaryDir = repoDestination.appendingPathComponent(folderName)
        // Secondary: any incomplete/cache copies under .cache/
        let cacheDir = repoDestination
            .appendingPathComponent(".cache/huggingface/download/\(folderName)", isDirectory: true)

        var deleted = false
        for dir in [primaryDir, cacheDir] {
            if fileManager.fileExists(atPath: dir.path) {
                do {
                    try fileManager.removeItem(at: dir)
                    Logger.shared.info("WhisperService: Removed '\(dir.lastPathComponent)' at \(dir.path)")
                    deleted = true
                } catch {
                    Logger.shared.error("WhisperService: Failed to remove \(dir.path): \(error)")
                }
            }
        }

        if deleted {
            checkDownloadedModels()
            if activeModel == modelName {
                Logger.shared.info("WhisperService: Deleted model was the active model. Unloading WhisperKit...")
                self.whisperKit = nil
                self.isReady = false
                DispatchQueue.main.async {
                    self.activeModel = ""
                    self.downloadState = "Model not downloaded."
                }
            }
            Logger.shared.info("WhisperService: Successfully deleted model '\(modelName)'")
        } else {
            Logger.shared.error("WhisperService: No files found to delete for model '\(modelName)'")
        }
    }
    
}

// MARK: - TranscriptionEngine Protocol
extension WhisperService: TranscriptionEngine {
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        guard isReady, let whisperKit = whisperKit else {
            Logger.shared.info("WhisperService: Cannot transcribe. WhisperKit is not ready yet.")
            DispatchQueue.main.async {
                self.delegate?.whisperServiceDidUpdateState("Model warming up...")
            }
            throw NSError(domain: "WhisperError", code: 1, userInfo: [NSLocalizedDescriptionKey: "WhisperKit is not ready yet."])
        }
        
        guard let floatChannelData = audioBuffer.floatChannelData else {
            throw NSError(domain: "WhisperError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid audio buffer"])
        }
        
        let frameLength = Int(audioBuffer.frameLength)
        let channelData = UnsafeBufferPointer<Float>(start: floatChannelData[0], count: frameLength)
        let audioArray = Array(channelData)

        // [DIAG] Step 2 — compare this between SPM build and Xcode build for the same speech duration.
        // Lower sample count in Xcode build = audio pipeline being cut short (H1) or mic silent (H3).
        let inputDurationSecs = Float(audioArray.count) / 16000.0
        Logger.shared.info("WhisperService: [DIAG] Input: \(audioArray.count) samples (≈\(String(format: "%.2f", inputDurationSecs))s)")

        let langCode = dictationLanguageCode
        let langDescription = langCode ?? "auto-detect"
        Logger.shared.info("WhisperService: Starting transcription on \(audioArray.count) frames using language: \(langDescription)")

        // IMPORTANT: `usePrefillPrompt` must be `true` when a specific language is chosen.
        // With `usePrefillPrompt: false`, WhisperKit ignores the `language` parameter entirely
        // and always auto-detects from the audio (detectLanguage defaults to !usePrefillPrompt).
        //
        // - Explicit language (e.g. "en", "id"): usePrefillPrompt=true → forces language tokens
        // - Auto-Detect (nil): usePrefillPrompt=false + detectLanguage=true → standard auto-detect
        let isExplicitLanguage = langCode != nil
        // Start greedy (temperature 0) for fastest decode path.
        // Cap fallback retries to 1 (default is 5) — each retry runs a full decoder pass.
        // For short dictation audio with a nearby microphone, the first greedy pass
        // almost always succeeds, so 5 retries are wasteful.
        let decodingOptions = DecodingOptions(
            language: langCode,
            temperature: 0.0,
            temperatureFallbackCount: 1,
            usePrefillPrompt: isExplicitLanguage,
            usePrefillCache: true,
            detectLanguage: isExplicitLanguage ? false : nil, // nil = WhisperKit defaults (auto-detect when prefill off)
            skipSpecialTokens: true,
            withoutTimestamps: true
            // Note: chunkingStrategy: .vad was removed — it runs a full neural VAD
            // pre-processing pass before encoding, adding ~200-600ms of latency on
            // short dictation clips. Our trimSilence() handles silence more cheaply.
        )
        
        // Trim leading/trailing silence before handing audio to the encoder.
        // If the entire recording is below the silence threshold (e.g. a stray hotkey
        // press with no speech), skip WhisperKit entirely — sending silence to the
        // encoder causes hallucinations like "you." or "thank you."
        guard let trimmedAudio = trimSilence(audioArray) else {
            Logger.shared.info("WhisperService: Audio is entirely silent — skipping encoder.")
            return ""
        }
        let silencePct = Int((1.0 - Float(trimmedAudio.count) / Float(audioArray.count)) * 100)
        Logger.shared.info("WhisperService: Trimmed audio from \(audioArray.count) to \(trimmedAudio.count) frames (\(silencePct)% silence removed)")
        
        let results = try await whisperKit.transcribe(audioArray: trimmedAudio, decodeOptions: decodingOptions)
        let combinedText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        Logger.shared.info("WhisperService: Transcription finished successfully.")
        
        return combinedText
    }
    // MARK: - Silence Trimming

    /// Removes leading and trailing silence from a raw PCM sample array.
    /// Returns `nil` when the audio is entirely silent (nothing above `threshold`),
    /// allowing the caller to skip the encoder entirely instead of hallucinating.
    ///
    /// - Parameters:
    ///   - samples:   Array of 32-bit float PCM samples (mono, 16 kHz).
    ///   - threshold: Amplitude below which a sample is considered silent.
    ///                0.01 ≈ -40 dBFS, appropriate for close-mic dictation.
    private func trimSilence(_ samples: [Float], threshold: Float = 0.01) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        guard let firstNonSilent = samples.firstIndex(where: { abs($0) > threshold }),
              let lastNonSilent  = samples.lastIndex(where:  { abs($0) > threshold }),
              firstNonSilent < lastNonSilent
        else {
            // Entirely silent — signal caller to skip encoding.
            return nil
        }
        return Array(samples[firstNonSilent...lastNonSilent])
    }
}
