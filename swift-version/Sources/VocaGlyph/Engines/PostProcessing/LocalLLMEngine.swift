import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - App-specific storage root

/// MLX/LLM model data lives under `~/Library/Caches/VocaGlyph/`.
/// HubApi appends `/{repoType}/{org}/{name}/` to downloadBase, so:
/// `downloadBase = ~/Library/Caches/VocaGlyph` → models land at
/// `~/Library/Caches/VocaGlyph/models/mlx-community/Qwen3-0.6B-4bit/`
/// This is the standard macOS location for re-downloadable cached data; no Full Disk Access required.
private func vocaGlyphCacheDir() -> URL {
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VocaGlyph", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Shared HubApi — sets downloadBase to `~/Library/Caches/VocaGlyph/`.
/// HubApi will create `VocaGlyph/models/<org>/<name>/` automatically.
private let vocaGlyphHubApi: HubApi = HubApi(downloadBase: vocaGlyphCacheDir())

// MARK: - Inference Provider Protocol (Injectable for testing)

/// Protocol abstracting the MLX inference layer. Concrete type is `MLXLMInferenceProvider`.
/// Test code injects `MockLocalLLMInferenceProvider` to avoid real model loading.
public protocol LocalLLMInferenceProvider: Sendable {
    func generate(prompt: String, modelId: String, configuration: LLMInferenceConfiguration) async throws -> String
    func loadContainer(modelId: String, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> Void
}

// MARK: - Real MLX Provider

/// Production inference provider backed by mlx-swift-lm.
/// Uses ModelContainer's AsyncStream-based generate API for Swift 6 concurrency safety.
public final class MLXLMInferenceProvider: LocalLLMInferenceProvider, @unchecked Sendable {
    private var cachedContainer: ModelContainer?
    private var cachedModelId: String?

    public init() {}

    public func loadContainer(modelId: String, progressHandler: @Sendable @escaping (Double) -> Void) async throws {
        let configuration = ModelConfiguration(id: modelId)
        let container = try await LLMModelFactory.shared.loadContainer(
            hub: vocaGlyphHubApi,
            configuration: configuration
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
        self.cachedContainer = container
        self.cachedModelId = modelId
    }

    public func generate(prompt: String, modelId: String, configuration: LLMInferenceConfiguration) async throws -> String {
        // Use cached container if available for the same model, otherwise load fresh
        let container: ModelContainer
        if let cached = cachedContainer, cachedModelId == modelId {
            container = cached
        } else {
            let modelConfiguration = ModelConfiguration(id: modelId)
            let loaded = try await LLMModelFactory.shared.loadContainer(
                hub: vocaGlyphHubApi,
                configuration: modelConfiguration
            ) { progress in
                Logger.shared.info("LocalLLMEngine: Auto-loading model \(Int(progress.fractionCompleted * 100))%")
            }
            self.cachedContainer = loaded
            self.cachedModelId = modelId
            container = loaded
        }
        let parameters = GenerateParameters(
            temperature: configuration.temperature,
            topP: configuration.topP,
            repetitionPenalty: configuration.repetitionPenalty,
            repetitionContextSize: configuration.repetitionContextSize
        )
        let userInput = UserInput(prompt: prompt)
        let input = try await container.prepare(input: userInput)
        let stream = try await container.generate(input: input, parameters: parameters)
        var output = ""
        for await generation in stream {
            switch generation {
            case .chunk(let text):
                output += text
            default:
                break
            }
        }
        return output
    }

    public func evict() {
        cachedContainer = nil
        cachedModelId = nil
        // Immediately flush MLX's GPU buffer pool so the multi-GB Metal buffers
        // that accumulate during inference are returned to the OS right away.
        // Without this, the pool is only trimmed on the next MLX allocation,
        // which leaves RAM elevated until the next dictation session.
        Memory.clearCache()
        Logger.shared.info("MLXLMInferenceProvider: Model evicted and GPU buffer cache cleared.")
    }

    /// `true` when a model container is currently held in Unified Memory.
    public var isContainerLoaded: Bool { cachedContainer != nil }
}

// MARK: - Error Type

public enum LocalLLMEngineError: LocalizedError, Equatable {
    case modelLoadFailed(String)
    case inferenceFailed(String)
    case insufficientMemory

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let reason):
            return "LocalLLMEngine: Model load failed — \(reason)"
        case .inferenceFailed(let reason):
            return "LocalLLMEngine: Inference failed — \(reason)"
        case .insufficientMemory:
            return "LocalLLMEngine: Insufficient unified memory to load model. Try a smaller model."
        }
    }
}

// MARK: - LocalLLMEngine Actor

/// On-device LLM post-processing engine powered by mlx-swift-lm.
///
/// - **Thread Safety**: Swift `actor` — inference is fully isolated from `@MainActor`.
/// - **Singleton**: Must be held as a `private lazy var` on `AppStateManager`.
/// - **Model Download**: Call `preloadModel(progressHandler:)` to eagerly download/cache
///   the model before the first dictation — use this to drive the Settings progress UI.
/// - **Memory**: Call `unloadModel()` to reclaim UMA used by the loaded model weights.
/// - **Disk**: Call `deleteModelFromDisk()` to remove the cached HuggingFace files.
public actor LocalLLMEngine: PostProcessingEngine {

    // MARK: - Properties

    private let modelId: String
    private let provider: LocalLLMInferenceProvider

    // MARK: - Init

    public init(
        modelId: String = "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
        provider: LocalLLMInferenceProvider? = nil
    ) {
        self.modelId = modelId
        self.provider = provider ?? MLXLMInferenceProvider()
    }

    // MARK: - Preload

    /// Eagerly downloads and caches the model, reporting progress 0.0→1.0 via `progressHandler`.
    /// After loading completes, runs a tiny dummy inference to pre-compile Metal shaders
    /// so the first real transcription session has no JIT compilation overhead.
    public func preloadModel(progressHandler: @Sendable @escaping (Double) -> Void) async throws {
        Logger.shared.info("LocalLLMEngine: Starting model preload for \(modelId)")
        do {
            try await provider.loadContainer(modelId: modelId, progressHandler: progressHandler)
            Logger.shared.info("LocalLLMEngine: Model preload complete. Running Metal shader warm-up...")
            await warmUpInference()
            Logger.shared.info("LocalLLMEngine: Warm-up complete. Model is ready for zero-latency inference.")
        } catch {
            Logger.shared.error("LocalLLMEngine: Preload failed — \(error.localizedDescription)")
            throw LocalLLMEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Returns `true` if the model container is currently loaded in Unified Memory.
    public func isModelLoaded() -> Bool {
        if let real = provider as? MLXLMInferenceProvider {
            return real.isContainerLoaded
        }
        return false
    }

    // MARK: - Delete from Disk

    /// Returns `true` if model files exist in the HuggingFace cache on disk.
    public func isModelDownloaded() -> Bool {
        return modelCacheDirectory()?.exists == true
    }

    /// Estimated disk usage of the downloaded model, in bytes. Returns nil if not downloaded.
    public func modelDiskUsageBytes() -> Int64? {
        guard let dir = modelCacheDirectory(), dir.exists else { return nil }
        return directorySize(at: dir.url)
    }

    /// Removes all cached model files from disk and evicts from RAM.
    ///
    /// The HuggingFace cache for `org/model-name` lives at:
    /// `~/.cache/huggingface/hub/models--org--model-name/`
    public func deleteModelFromDisk() throws {
        // Evict from RAM first
        if let real = provider as? MLXLMInferenceProvider {
            real.evict()
        }
        guard let entry = modelCacheDirectory(), entry.exists else {
            Logger.shared.info("LocalLLMEngine: No cached files found for \(modelId) — nothing to delete.")
            return
        }
        do {
            try FileManager.default.removeItem(at: entry.url)
            Logger.shared.info("LocalLLMEngine: Deleted model cache at \(entry.url.path)")
        } catch {
            Logger.shared.error("LocalLLMEngine: Failed to delete model cache — \(error.localizedDescription)")
            throw LocalLLMEngineError.modelLoadFailed("Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Unload from RAM

    /// Evicts the loaded model weights from Unified Memory without touching disk.
    public func unloadModel() {
        if let real = provider as? MLXLMInferenceProvider {
            real.evict()
        }
        Logger.shared.info("LocalLLMEngine: Model unloaded from memory.")
    }

    // MARK: - PostProcessingEngine Conformance

    public func refine(text: String, prompt: String) async throws -> String {
        // Read user-configured parameters from UserDefaults at inference time.
        let inferenceConfig = LLMInferenceConfiguration.fromUserDefaults()
        PostProcessingLogger.shared.info("LocalLLMEngine: [REQUEST] model=\(modelId) input=\(text.count) chars")
        PostProcessingLogger.shared.info("LocalLLMEngine: [REQUEST] Prompt: '\(prompt)'")
        PostProcessingLogger.shared.info("LocalLLMEngine: [REQUEST] Input text: '\(text)'")
        PostProcessingLogger.shared.info("LocalLLMEngine: [PARAMS] temperature=\(inferenceConfig.temperature) topP=\(inferenceConfig.topP) repetitionPenalty=\(inferenceConfig.repetitionPenalty.map { String($0) } ?? "nil")")
        let fullPrompt = buildPrompt(system: prompt, userText: text)
        do {
            let rawOutput = try await provider.generate(prompt: fullPrompt, modelId: modelId, configuration: inferenceConfig)
            PostProcessingLogger.shared.info("LocalLLMEngine: [RESPONSE] Raw model output (\(rawOutput.count) chars): '\(rawOutput)'")
            // Qwen3 and other "thinking" models emit <think>…</think> before the answer.
            // Strip it so only the actual refined text is returned.
            let withoutThink = rawOutput.replacingOccurrences(
                of: #"<think>[\s\S]*?</think>"#,
                with: "",
                options: .regularExpression
            )
            let trimmed = withoutThink.trimmingCharacters(in: .whitespacesAndNewlines)
            PostProcessingLogger.shared.info("LocalLLMEngine: [RESULT] '\(trimmed)'")
            return trimmed
        } catch let error as LocalLLMEngineError {
            throw error
        } catch {
            Logger.shared.error("LocalLLMEngine: Inference error — \(error.localizedDescription)")
            throw LocalLLMEngineError.inferenceFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Runs a minimal single-token inference to trigger Metal shader JIT compilation.
    /// Result is discarded — this purely pre-warms the GPU compute graph so the
    /// first real user session has no compilation delay (typically saves 1–3 seconds).
    private func warmUpInference() async {
        let warmUpPrompt = buildPrompt(system: "You are a helpful assistant.", userText: "Hi")
        _ = try? await provider.generate(prompt: warmUpPrompt, modelId: modelId, configuration: .default)
        Logger.shared.info("LocalLLMEngine: Metal shader warm-up inference complete.")
    }

    private struct CacheEntry {
        let url: URL
        var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    }

    /// Returns the directory where HubApi caches the model on disk.
    /// HubApi path: `downloadBase/models/{org}/{name}/`
    /// With downloadBase `~/Library/Caches/VocaGlyph` → `~/Library/Caches/VocaGlyph/models/mlx-community/Qwen3-0.6B-4bit/`
    private func modelCacheDirectory() -> CacheEntry? {
        var dir = vocaGlyphCacheDir().appendingPathComponent("models")
        for component in modelId.split(separator: "/") {
            dir = dir.appendingPathComponent(String(component))
        }
        return CacheEntry(url: dir)
    }

    private func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func buildPrompt(system: String, userText: String) -> String {
        return "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(userText)<|im_end|>\n<|im_start|>assistant\n"
    }
}
