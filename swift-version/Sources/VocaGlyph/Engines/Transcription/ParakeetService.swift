import Foundation
import AVFoundation
import FluidAudio

/// Parakeet TDT CoreML transcription service via FluidInference/FluidAudio.
/// Mirrors the `WhisperService` @Published property pattern and @MainActor dispatch rules.
/// Conforms to `TranscriptionEngine` for seamless `EngineRouter` integration.
class ParakeetService: ObservableObject, @unchecked Sendable {

    // MARK: - Model Version

    enum ModelVersion {
        /// Multilingual model supporting 25 European languages + English.
        case v3
        /// English-only model — smaller memory footprint.
        case v2

        /// Maps to the FluidAudio top-level AsrModelVersion enum (0.12.1+).
        var asrModelVersion: AsrModelVersion {
            switch self {
            case .v3: return .v3
            case .v2: return .v2
            }
        }

        /// The canonical model ID string used in UI and UserDefaults.
        var modelId: String {
            switch self {
            case .v3: return "parakeet-v3"
            case .v2: return "parakeet-v2"
            }
        }

        init?(modelId: String) {
            switch modelId {
            case "parakeet-v3": self = .v3
            case "parakeet-v2": self = .v2
            default: return nil
            }
        }
    }

    // MARK: - Published State (mirrors WhisperService naming)

    @Published private(set) var isReady: Bool = false
    @Published var downloadState: String = "Not Initialized"
    @Published var activeModel: String = ""
    @Published var downloadedModels: Set<String> = []

    /// Non-nil while a model is actively downloading or initializing.
    /// Used by ModelSettingsView to show a loading indicator on the correct card.
    @Published var downloadingModelId: String? = nil

    /// 0.0 → 1.0 loading progress. Driven by initialization phases so 
    /// `AppStateManager` can forward it to `RecordingOverlayView`.
    /// Phases: downloading = 0.25, loading into ANE = 0.75, ready = 1.0.
    @Published var loadingProgress: Double = 0.0

    // MARK: - Private

    private var asrManager: AsrManager?
    private var currentVersion: ModelVersion?

    // MARK: - Init

    init() {
        Logger.shared.info("ParakeetService: Initialized.")
        restoreDownloadedModelsFromDisk()
        Task { await autoInitializeIfNeeded() }
    }

    /// Scans FluidAudio's cache directories on disk and pre-populates `downloadedModels`
    /// so the Settings UI shows the correct DOWNLOADED badge on every app launch.
    /// Thread-safe: assigns synchronously when already on the main thread (init, deleteModel)
    /// so that `autoInitializeIfNeeded()` sees the populated set immediately.
    /// Dispatches asynchronously to the main thread only if called from a background context.
    private func restoreDownloadedModelsFromDisk() {
        var found: Set<String> = []
        for version in [ModelVersion.v3, ModelVersion.v2] {
            let dir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
            // A downloaded model directory will contain at least one .mlmodelc sub-directory.
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ), !contents.isEmpty {
                found.insert(version.modelId)
                Logger.shared.info("ParakeetService: Found cached model '\(version.modelId)' at \(dir.lastPathComponent)")
            }
        }
        // If we're already on the main thread (init, deleteModel @MainActor),
        // assign synchronously so that autoInitializeIfNeeded() and any other
        // code following this call sees the updated set immediately.
        // Only dispatch async when called from a background context.
        if Thread.isMainThread {
            downloadedModels = found
        } else {
            DispatchQueue.main.async { self.downloadedModels = found }
        }
    }

    // MARK: - Public API

    /// Rescans FluidAudio's cache directories on disk and updates `downloadedModels`.
    /// Mirrors `WhisperService.checkDownloadedModels()`. Called after `deleteModel(id:)`
    /// to ensure the UI reflects the actual on-disk state.
    func checkDownloadedModels() {
        restoreDownloadedModelsFromDisk()
    }

    /// Auto-initializes the selected Parakeet model on launch if it is already on disk.
    /// Called from `init()` — mirrors `WhisperService.autoInitialize()`.
    /// NEVER triggers a network download: the guard checks `downloadedModels` (populated
    /// by `restoreDownloadedModelsFromDisk()`) before calling `initialize()`.
    private func autoInitializeIfNeeded() async {
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        guard selected.hasPrefix("parakeet-"),
              let version = ModelVersion(modelId: selected),
              downloadedModels.contains(selected) else {
            if selected.hasPrefix("parakeet-") && !downloadedModels.contains(selected) {
                Logger.shared.info("ParakeetService: Selected parakeet model '\(selected)' not on disk — staying idle.")
            }
            return
        }

        Logger.shared.info("ParakeetService: Auto-initializing \(selected) on launch...")
        await initialize(version: version)
    }

    /// Downloads and loads the CoreML model for the given version into ANE memory.
    /// Updates @Published state on @MainActor throughout.
    /// - Parameter version: The Parakeet model version to load (.v2 or .v3)
    func initialize(version: ModelVersion) async {
        Logger.shared.info("ParakeetService: Beginning initialization for \(version.modelId)...")

        // AC#4: Concurrent download guard — if another model is already downloading,
        // ignore this call. If the same model is requested again, allow it (idempotent).
        guard downloadingModelId == nil || downloadingModelId == version.modelId else {
            Logger.shared.info("ParakeetService: Already loading \(downloadingModelId!) — ignoring \(version.modelId).")
            return
        }

        await MainActor.run {
            self.downloadState = "Downloading \(version.modelId)..."
            self.isReady = false
            self.downloadingModelId = version.modelId
            self.loadingProgress = 0.1  // signals "started" to the overlay immediately
        }

        do {
            Logger.shared.info("ParakeetService: Calling AsrModels.downloadAndLoad(version: \(version.modelId))")
            await MainActor.run { self.loadingProgress = 0.25 }

            // FluidAudio doesn't expose a download progress callback, so we trickle
            // from 0.25 → 0.58 by +2% every 2s to give the user visible movement.
            // The task is cancelled the moment downloadAndLoad() returns.
            let trickleTask = Task {
                var current = 0.25
                while !Task.isCancelled && current < 0.58 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                    if Task.isCancelled { break }
                    current = min(current + 0.02, 0.58)
                    await MainActor.run { self.loadingProgress = current }
                }
            }

            let models = try await AsrModels.downloadAndLoad(version: version.asrModelVersion)
            trickleTask.cancel() // download done — stop trickle immediately

            // Mark files as present on disk immediately after FluidAudio succeeds.
            // This ensures the card shows DOWNLOADED even if the ANE load step fails.
            await MainActor.run {
                self.downloadedModels.insert(version.modelId)
                self.downloadState = "Loading into ANE memory..."
                self.loadingProgress = 0.65
            }

            // Step 2: Initialize the AsrManager with the loaded model files.
            Logger.shared.info("ParakeetService: Initializing AsrManager...")
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)

            await MainActor.run { self.loadingProgress = 0.88 }

            // Step 3: Commit state — all @Published mutations on @MainActor.
            await MainActor.run {
                self.asrManager = manager
                self.isReady = true
                self.currentVersion = version
                self.activeModel = version.modelId
                self.downloadState = "Ready"
                self.downloadedModels.insert(version.modelId)
                self.downloadingModelId = nil
                self.loadingProgress = 1.0
            }

            Logger.shared.info("ParakeetService: \(version.modelId) is ready on ANE.")

            // Reset progress to 0 after a short delay so it doesn't permanently sit at 1.0
            // and pollute AppStateManager's modelLoadingProgress when Whisper loads later.
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            await MainActor.run { self.loadingProgress = 0.0 }

        } catch {
            // AC#9: set downloadState to "Failed to load", keep isReady = false.
            Logger.shared.error("ParakeetService: Failed to load \(version.modelId) — \(error.localizedDescription)")
            await MainActor.run {
                self.downloadState = "Failed to load"
                self.isReady = false
                self.downloadingModelId = nil
                self.loadingProgress = 0.0
            }
        }
    }


    /// Parses a model ID string and fires an async initialization in the background.
    /// Called by "Use Model" — downloads if needed AND switches the active engine.
    func changeModel(to modelName: String) {
        Logger.shared.info("ParakeetService: Requested model change to '\(modelName)'")
        guard let version = ModelVersion(modelId: modelName) else {
            Logger.shared.error("ParakeetService: Unknown model ID '\(modelName)' — ignoring.")
            return
        }
        Task {
            await initialize(version: version)
        }
    }

    /// Downloads model files to disk WITHOUT switching the active engine.
    /// Called by the "Download" card button — preserves the currently active model.
    func downloadOnly(id: String) {
        guard let version = ModelVersion(modelId: id) else {
            Logger.shared.error("ParakeetService: Cannot download unknown model ID '\(id)'")
            return
        }
        // Don't start if already downloaded or already downloading this model.
        guard !downloadedModels.contains(id), downloadingModelId == nil else {
            Logger.shared.info("ParakeetService: '\(id)' already downloaded or download in progress — skipping.")
            return
        }
        Task {
            await performDownloadOnly(version: version)
        }
    }

    private func performDownloadOnly(version: ModelVersion) async {
        Logger.shared.info("ParakeetService: Download-only for '\(version.modelId)'...")

        await MainActor.run {
            self.downloadingModelId = version.modelId
            self.loadingProgress = 0.25
        }

        // Trickle: 0.25 → 0.58 while waiting for FluidAudio download (files only).
        let trickleTask = Task {
            var current = 0.25
            while !Task.isCancelled && current < 0.58 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                current = min(current + 0.02, 0.58)
                await MainActor.run { self.loadingProgress = current }
            }
        }

        do {
            _ = try await AsrModels.download(version: version.asrModelVersion)
            trickleTask.cancel()

            // Mark files present on disk — do NOT touch activeModel or asrManager.
            await MainActor.run {
                self.downloadedModels.insert(version.modelId)
                self.downloadingModelId = nil
                self.loadingProgress = 0.0
            }
            Logger.shared.info("ParakeetService: Download-only complete for '\(version.modelId)'.")
        } catch {
            trickleTask.cancel()
            Logger.shared.error("ParakeetService: Download-only failed for '\(version.modelId)' — \(error.localizedDescription)")
            await MainActor.run {
                self.downloadingModelId = nil
                self.loadingProgress = 0.0
            }
        }
    }

    /// Deletes the cached CoreML model files for the given model ID.
    /// Uses `AsrModels.defaultCacheDirectory(for:)` — the same path FluidAudio writes to.
    @MainActor
    func deleteModel(id: String) {
        guard let version = ModelVersion(modelId: id) else {
            Logger.shared.error("ParakeetService: Cannot delete unknown model ID '\(id)'")
            return
        }
        let cacheDir = AsrModels.defaultCacheDirectory(for: version.asrModelVersion)
        Logger.shared.info("ParakeetService: Deleting model at \(cacheDir.path)")
        do {
            if FileManager.default.fileExists(atPath: cacheDir.path) {
                try FileManager.default.removeItem(at: cacheDir)
                Logger.shared.info("ParakeetService: Deleted model '\(id)' from cache.")
            }
            downloadedModels.remove(id)
            if activeModel == id {
                isReady = false
                activeModel = ""
                asrManager = nil
                currentVersion = nil
                downloadState = "Not Initialized"
                loadingProgress = 0.0
            }
            // AC#7: Clear stale loading indicators if the deleted model was mid-download.
            if downloadingModelId == id {
                downloadingModelId = nil
                loadingProgress = 0.0
            }
            // AC#3: Resync downloadedModels from disk after delete (mirrors WhisperService.checkDownloadedModels()).
            checkDownloadedModels()
        } catch {
            Logger.shared.error("ParakeetService: Failed to delete model '\(id)' — \(error.localizedDescription)")
        }
    }
}

// MARK: - TranscriptionEngine Protocol

extension ParakeetService: TranscriptionEngine {
    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> String {
        guard isReady, let manager = asrManager else {
            Logger.shared.info("ParakeetService: Cannot transcribe — model not ready yet.")
            throw NSError(
                domain: "ParakeetError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Parakeet model is not ready yet. Please wait for download and initialization."]
            )
        }

        // AC#6: Extract samples for amplitude-based silence detection (mirrors WhisperService).
        guard let channelData = audioBuffer.floatChannelData else {
            throw NSError(
                domain: "ParakeetError",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid audio buffer: no channel data"]
            )
        }
        let frameLength = Int(audioBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer<Float>(start: channelData[0], count: frameLength))

        guard let trimmedSamples = trimSilence(samples) else {
            Logger.shared.info("ParakeetService: Audio is entirely silent — skipping ANE inference.")
            return ""
        }

        let silencePct = Int((1.0 - Float(trimmedSamples.count) / Float(max(samples.count, 1))) * 100)
        Logger.shared.info("ParakeetService: Trimmed \(silencePct)% silence. Frames: \(samples.count) → \(trimmedSamples.count)")

        // Rebuild a trimmed AVAudioPCMBuffer for FluidAudio.
        let format = audioBuffer.format
        let trimmedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(trimmedSamples.count))!
        trimmedBuffer.frameLength = AVAudioFrameCount(trimmedSamples.count)
        trimmedSamples.withUnsafeBufferPointer { ptr in
            trimmedBuffer.floatChannelData![0].initialize(from: ptr.baseAddress!, count: trimmedSamples.count)
        }

        Logger.shared.info("ParakeetService: Starting transcription (model: \(activeModel), frames: \(trimmedBuffer.frameLength))")
        let result = try await manager.transcribe(trimmedBuffer)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.shared.info("ParakeetService: Transcription complete — '\(text)'")
        return text
    }
}

// MARK: - Silence Trimming

extension ParakeetService {
    /// Removes leading and trailing silence from a raw PCM sample array.
    /// Returns `nil` when the audio is entirely silent (all samples ≤ threshold),
    /// allowing the caller to skip ANE inference instead of producing a hallucination.
    /// Mirrors `WhisperService.trimSilence()` — identical logic, engine-agnostic.
    func trimSilence(_ samples: [Float], threshold: Float = 0.01) -> [Float]? {
        guard !samples.isEmpty else { return nil }
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last  = samples.lastIndex(where:  { abs($0) > threshold }),
              first < last
        else { return nil }
        return Array(samples[first...last])
    }
}
