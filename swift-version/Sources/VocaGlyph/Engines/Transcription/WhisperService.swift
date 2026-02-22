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
    
    // Base directory for all VocaGlyph model storage
    private var baseDirectoryPath: URL {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let vocaGlyphDir = homeDir.appendingPathComponent(".VocaGlyph", isDirectory: true)
        let baseDir = vocaGlyphDir.appendingPathComponent("models", isDirectory: true)
        if !fileManager.fileExists(atPath: baseDir.path) {
            do {
                try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create models directory: \(error)")
            }
        }
        return baseDir
    }

    // The default HuggingFace repo for WhisperKit CoreML models
    static let defaultModelRepo = "argmaxinc/whisperkit-coreml"

    
    // The actual directory where WhisperKit saves models for a given repo
    private func modelsDirectory(for repo: String = WhisperService.defaultModelRepo) -> URL {
        return baseDirectoryPath.appendingPathComponent("models/\(repo)")
    }
    
    // Legacy accessor kept for compatibility (points to default repo)
    private var actualModelsDirectory: URL {
        modelsDirectory(for: WhisperService.defaultModelRepo)
    }
    
    init() {
        checkDownloadedModels()
        Task {
            await autoInitialize()
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
        let modelsDir = actualModelsDirectory

        var downloaded = Set<String>()
        do {
            let items = try fileManager.contentsOfDirectory(atPath: modelsDir.path)
            for item in items {
                // Strip known prefixes to get back to the variant name
                if item.hasPrefix("openai_whisper-") {
                    downloaded.insert(String(item.dropFirst("openai_whisper-".count)))
                } else if item.hasPrefix("distil-whisper_") {
                    downloaded.insert(item) // keep full name e.g. distil-whisper_distil-large-v3
                }
            }
        } catch {
            print("No models downloaded yet or directory missing.")
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
        
        let available = getDownloadedModelsSync()
        if available.contains(defaultModelName) {
            await initializeWhisper(modelName: defaultModelName)
        } else if let firstAvailable = available.first {
            // Fallback to whichever model is available so the user isn't outright broken
            DispatchQueue.main.async {
                self.downloadState = "Falling back to \(firstAvailable)..."
            }
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
            
            // On-disk folder name depends on the model prefix convention
            let folderName = modelName.hasPrefix("distil-whisper_")
                ? modelName
                : "openai_whisper-\(modelName)"
            let modelPath = actualModelsDirectory.appendingPathComponent(folderName)
            
            Logger.shared.info("WhisperService: Model available at \(modelPath). Loading into memory...")
            whisperKit = try await WhisperKit(modelFolder: modelPath.path)
            isReady = true
            
            Logger.shared.info("WhisperService: WhisperKit is ready using model: \(modelName)")
            
            DispatchQueue.main.async {
                self.activeModel = modelName
                UserDefaults.standard.set(modelName, forKey: "selectedModel")
                self.loadingModel = nil
                self.downloadState = "Ready"
            }
            
            delegate?.whisperServiceDidUpdateState("Ready")
        } catch {
            Logger.shared.error("WhisperService: Failed to initialize WhisperKit: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.loadingModel = nil
            }
            delegate?.whisperServiceDidUpdateState("Failed")
        }
    }
    
    // MARK: - Dynamic Configuration
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
        let modelDir = actualModelsDirectory.appendingPathComponent(folderName)
        
        do {
            try fileManager.removeItem(at: modelDir)
            checkDownloadedModels()
            
            // If we deleted the currently active model, unload it.
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
        } catch {
            Logger.shared.error("WhisperService: Failed to delete model '\(modelName)': \(error)")
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
        let decodingOptions = DecodingOptions(
            language: langCode,
            usePrefillPrompt: isExplicitLanguage,
            usePrefillCache: true,
            detectLanguage: isExplicitLanguage ? false : nil, // nil = WhisperKit defaults (auto-detect when prefill off)
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        
        let results = try await whisperKit.transcribe(audioArray: audioArray, decodeOptions: decodingOptions)
        let combinedText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        Logger.shared.info("WhisperService: Transcription finished successfully.")
        
        return combinedText
    }
}
